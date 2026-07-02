import CoreMediaIO
import CoreVideo
import Darwin
import Foundation
import IOKit.audio
import os.log

let CameraFrameRate = 30
private let cameraWidth: Int32 = 1920
private let cameraHeight: Int32 = 1080

final class CameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!

    private var streamSource: CameraStreamSource!
    private var streamSink: CameraStreamSink!

    private var streamingCounter: UInt32 = 0
    private var streamingSinkCounter: UInt32 = 0
    private var placeholderTimer: DispatchSourceTimer?
    private var consumeBufferTimer: DispatchSourceTimer?

    private let timerQueue = DispatchQueue(
        label: "MacVirtualCamera.CameraExtension",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .workItem,
        target: .global(qos: .userInteractive))

    private var videoDescription: CMFormatDescription!
    private var bufferPool: CVPixelBufferPool!
    private var bufferAuxAttributes: NSDictionary!

    private var sinkStarted = false

    init(localizedName: String, deviceUUID: UUID, sourceUUID: UUID, sinkUUID: UUID) {
        super.init()

        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: deviceUUID,
            legacyDeviceID: nil,
            source: self)

        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: cameraWidth,
            height: cameraHeight,
            extensions: nil,
            formatDescriptionOut: &videoDescription)

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: cameraWidth,
            kCVPixelBufferHeightKey: cameraHeight,
            kCVPixelBufferPixelFormatTypeKey: videoDescription.mediaSubType,
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: CFTypeRef](),
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &bufferPool)
        bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]

        let streamFormat = CMIOExtensionStreamFormat(
            formatDescription: videoDescription,
            maxFrameDuration: CMTime(value: 1, timescale: Int32(CameraFrameRate)),
            minFrameDuration: CMTime(value: 1, timescale: Int32(CameraFrameRate)),
            validFrameDurations: nil)

        streamSource = CameraStreamSource(
            localizedName: "MacVirtualCamera Source",
            streamID: sourceUUID,
            streamFormat: streamFormat,
            device: device)

        streamSink = CameraStreamSink(
            localizedName: "MacVirtualCamera Sink",
            streamID: sinkUUID,
            streamFormat: streamFormat,
            device: device)

        do {
            try device.addStream(streamSource.stream)
            try device.addStream(streamSink.stream)
        } catch {
            fatalError("Failed to add virtual camera streams: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws
        -> CMIOExtensionDeviceProperties
    {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])

        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }

        if properties.contains(.deviceModel) {
            deviceProperties.model = "MacVirtualCamera"
        }

        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
    }

    func startStreaming() {
        streamingCounter += 1

        guard placeholderTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(CameraFrameRate), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.sendPlaceholderIfNeeded()
        }
        timer.resume()
        placeholderTimer = timer
    }

    func stopStreaming() {
        if streamingCounter > 1 {
            streamingCounter -= 1
            return
        }

        streamingCounter = 0
        placeholderTimer?.cancel()
        placeholderTimer = nil
    }

    func startStreamingSink(client: CMIOExtensionClient) {
        streamingSinkCounter += 1
        sinkStarted = true

        guard consumeBufferTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / (Double(CameraFrameRate) * 3.0), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.consumeBuffer(client)
        }
        timer.resume()
        consumeBufferTimer = timer
    }

    func stopStreamingSink() {
        sinkStarted = false

        if streamingSinkCounter > 1 {
            streamingSinkCounter -= 1
            return
        }

        streamingSinkCounter = 0
        consumeBufferTimer?.cancel()
        consumeBufferTimer = nil
    }

    private func consumeBuffer(_ client: CMIOExtensionClient) {
        guard sinkStarted else {
            return
        }

        streamSink.stream.consumeSampleBuffer(from: client) {
            [weak self] sampleBuffer, sequenceNumber, _, _, _ in
            guard let self, let sampleBuffer else {
                return
            }

            if self.streamingCounter > 0 {
                self.streamSource.stream.send(
                    sampleBuffer,
                    discontinuity: [],
                    hostTimeInNanoseconds: UInt64(sampleBuffer.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
            }

            let output = CMIOExtensionScheduledOutput(
                sequenceNumber: sequenceNumber,
                hostTimeInNanoseconds: UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * Double(NSEC_PER_SEC)))
            self.streamSink.stream.notifyScheduledOutputChanged(output)
        }
    }

    private func sendPlaceholderIfNeeded() {
        guard !sinkStarted, streamingCounter > 0 else {
            return
        }

        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            bufferPool,
            bufferAuxAttributes,
            &pixelBuffer)

        guard result == kCVReturnSuccess, let pixelBuffer else {
            os_log(.error, "Unable to allocate placeholder buffer: \(result)")
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo()
        timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
        timing.duration = CMTime(value: 1, timescale: Int32(CameraFrameRate))
        timing.decodeTimeStamp = .invalid

        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)

        if let sampleBuffer {
            streamSource.stream.send(
                sampleBuffer,
                discontinuity: [],
                hostTimeInNanoseconds: UInt64(timing.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
        }
    }
}
