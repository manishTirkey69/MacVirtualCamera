import CoreMediaIO
import Foundation

let deviceUUIDString = Bundle.main.object(forInfoDictionaryKey: "MacVirtualCameraDeviceUUID") as? String
let sourceUUIDString = Bundle.main.object(forInfoDictionaryKey: "MacVirtualCameraSourceUUID") as? String
let sinkUUIDString = Bundle.main.object(forInfoDictionaryKey: "MacVirtualCameraSinkUUID") as? String

guard let deviceUUIDString, let sourceUUIDString, let sinkUUIDString,
      let deviceUUID = UUID(uuidString: deviceUUIDString),
      let sourceUUID = UUID(uuidString: sourceUUIDString),
      let sinkUUID = UUID(uuidString: sinkUUIDString)
else {
    fatalError("Invalid MacVirtualCamera UUID configuration")
}

let providerSource = CameraProviderSource(
    clientQueue: nil,
    deviceUUID: deviceUUID,
    sourceUUID: sourceUUID,
    sinkUUID: sinkUUID)

CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
