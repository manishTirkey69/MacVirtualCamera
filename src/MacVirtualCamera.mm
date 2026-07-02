#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreVideo/CoreVideo.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <SystemExtensions/SystemExtensions.h>

#ifndef MAC_VIRTUAL_CAMERA_EXTENSION_ID
#define MAC_VIRTUAL_CAMERA_EXTENSION_ID "com.obsproject.MacVirtualCamera.CameraExtension"
#endif

#ifndef MAC_VIRTUAL_CAMERA_DEVICE_UUID
#define MAC_VIRTUAL_CAMERA_DEVICE_UUID "7E3F37E2-5F41-44B4-9B73-0B98F3D66E91"
#endif

static constexpr int32_t kFrameRate = 30;
static constexpr int32_t kFrameWidth = 1920;
static constexpr int32_t kFrameHeight = 1080;
static constexpr FourCharCode kPixelFormat = kCVPixelFormatType_32BGRA;

@class MacVirtualCameraApp;

@interface SystemExtensionDelegate : NSObject <OSSystemExtensionRequestDelegate>
@property BOOL installed;
@property(copy) NSString *lastError;
@end

@implementation SystemExtensionDelegate

- (OSSystemExtensionReplacementAction)request:(OSSystemExtensionRequest *)request
                 actionForReplacingExtension:(OSSystemExtensionProperties *)existing
                               withExtension:(OSSystemExtensionProperties *)extension
{
    (void) request;
    (void) existing;
    (void) extension;
    return OSSystemExtensionReplacementActionReplace;
}

- (void)request:(OSSystemExtensionRequest *)request didFailWithError:(NSError *)error
{
    (void) request;
    self.installed = NO;
    self.lastError = error.localizedDescription;
}

- (void)request:(OSSystemExtensionRequest *)request didFinishWithResult:(OSSystemExtensionRequestResult)result
{
    (void) request;
    self.installed = YES;

    if (result == OSSystemExtensionRequestWillCompleteAfterReboot) {
        self.lastError = @"Camera extension will activate after restart";
    } else {
        self.lastError = nil;
    }
}

- (void)requestNeedsUserApproval:(OSSystemExtensionRequest *)request
{
    (void) request;
    self.installed = NO;
    self.lastError = @"Approve the camera extension in System Settings";
}

@end

@interface ScreenCaptureOutput : NSObject <SCStreamOutput, SCStreamDelegate>
@property(weak) MacVirtualCameraApp *owner;
@end

@interface MacVirtualCameraApp : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSMenuItem *startItem;
@property NSMenuItem *stopItem;
@property NSMenuItem *screenItem;
@property NSMenuItem *statusItemText;
- (IBAction)startVirtualCamera:(id)sender;
- (IBAction)stopVirtualCamera:(id)sender;
- (void)handleScreenSampleBuffer:(CMSampleBufferRef)sampleBuffer;
@end

@implementation ScreenCaptureOutput

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error
{
    (void) stream;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.owner stopVirtualCamera:nil];
        self.owner.statusItemText.title = [NSString stringWithFormat:@"Screen capture stopped: %@", error.localizedDescription];
    });
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type
{
    (void) stream;

    if (type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sampleBuffer)) {
        return;
    }

    [self.owner handleScreenSampleBuffer:sampleBuffer];
}

@end

@implementation MacVirtualCameraApp {
    SystemExtensionDelegate *_extensionDelegate;
    ScreenCaptureOutput *_captureOutput;
    SCStream *_screenStream;
    dispatch_queue_t _screenQueue;
    CMSimpleQueueRef _cmioQueue;
    CMIODeviceID _cmioDeviceID;
    CMIOStreamID _cmioSinkStreamID;
    CMVideoFormatDescriptionRef _formatDescription;
    BOOL _starting;
    BOOL _running;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void) notification;

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    _screenQueue = dispatch_queue_create("MacVirtualCamera.ScreenCapture", DISPATCH_QUEUE_SERIAL);
    _extensionDelegate = [[SystemExtensionDelegate alloc] init];

    [self buildMenu];
    [self installCameraExtension];
    [self updateMenu];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    (void) notification;
    [self stopVirtualCamera:nil];
}

- (void)buildMenu
{
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"Mac VCam";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"MacVirtualCamera"];
    self.statusItemText = [[NSMenuItem alloc] initWithTitle:@"Installing camera extension..."
                                                     action:nil
                                              keyEquivalent:@""];
    [menu addItem:self.statusItemText];
    [menu addItem:NSMenuItem.separatorItem];

    self.startItem = [[NSMenuItem alloc] initWithTitle:@"Start Virtual Camera"
                                                action:@selector(startVirtualCamera:)
                                         keyEquivalent:@""];
    self.startItem.target = self;
    [menu addItem:self.startItem];

    self.stopItem = [[NSMenuItem alloc] initWithTitle:@"Stop Virtual Camera"
                                               action:@selector(stopVirtualCamera:)
                                        keyEquivalent:@""];
    self.stopItem.target = self;
    [menu addItem:self.stopItem];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *sourceRoot = [[NSMenuItem alloc] initWithTitle:@"Source Selection" action:nil keyEquivalent:@""];
    NSMenu *sourceMenu = [[NSMenu alloc] initWithTitle:@"Source Selection"];
    self.screenItem = [[NSMenuItem alloc] initWithTitle:@"Screen" action:nil keyEquivalent:@""];
    self.screenItem.state = NSControlStateValueOn;
    [sourceMenu addItem:self.screenItem];
    sourceRoot.submenu = sourceMenu;
    [menu addItem:sourceRoot];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];
    quitItem.target = NSApp;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (void)installCameraExtension
{
    OSSystemExtensionRequest *request = [OSSystemExtensionRequest
        activationRequestForExtension:@MAC_VIRTUAL_CAMERA_EXTENSION_ID
                                queue:dispatch_get_main_queue()];
    request.delegate = _extensionDelegate;
    [OSSystemExtensionManager.sharedManager submitRequest:request];
}

- (IBAction)startVirtualCamera:(id)sender
{
    (void) sender;

    if (_starting || _running) {
        return;
    }

    if (!CGPreflightScreenCaptureAccess()) {
        CGRequestScreenCaptureAccess();
        if (!CGPreflightScreenCaptureAccess()) {
            self.statusItemText.title = @"Screen Recording permission required";
            [self updateMenu];
            return;
        }
    }

    _starting = YES;
    self.statusItemText.title = @"Starting virtual camera...";
    [self updateMenu];

    if (![self startCMIOSink]) {
        _starting = NO;
        [self updateMenu];
        return;
    }

    [self startScreenCapture];
}

- (IBAction)stopVirtualCamera:(id)sender
{
    (void) sender;

    _running = NO;
    _starting = NO;

    if (_screenStream) {
        SCStream *stream = _screenStream;
        _screenStream = nil;
        [stream stopCaptureWithCompletionHandler:^(NSError *error) {
            (void) error;
        }];
    }

    [self closeCMIOSink];

    self.statusItemText.title = @"Ready";
    [self updateMenu];
}

- (void)closeCMIOSink
{
    @synchronized(self) {
        if (_cmioDeviceID && _cmioSinkStreamID) {
            CMIODeviceStopStream(_cmioDeviceID, _cmioSinkStreamID);
            _cmioDeviceID = 0;
            _cmioSinkStreamID = 0;
        }

        if (_formatDescription) {
            CFRelease(_formatDescription);
            _formatDescription = nil;
        }

        _cmioQueue = nil;
    }
}

- (BOOL)startCMIOSink
{
    if (_cmioQueue) {
        return YES;
    }

    _cmioDeviceID = [self findCameraDeviceID];
    if (!_cmioDeviceID) {
        NSString *detail = _extensionDelegate.lastError ?: @"Camera extension unavailable";
        self.statusItemText.title = detail;
        return NO;
    }

    UInt32 size = 0;
    UInt32 used = 0;
    CMIOObjectPropertyAddress address = {
        kCMIODevicePropertyStreams,
        kCMIOObjectPropertyScopeGlobal,
        kCMIOObjectPropertyElementMain,
    };

    if (CMIOObjectGetPropertyDataSize(_cmioDeviceID, &address, 0, NULL, &size) != noErr ||
        size < 2 * sizeof(CMIOStreamID)) {
        self.statusItemText.title = @"Camera extension stream unavailable";
        return NO;
    }

    NSMutableData *streamData = [NSMutableData dataWithLength:size];
    if (CMIOObjectGetPropertyData(_cmioDeviceID, &address, 0, NULL, size, &used, streamData.mutableBytes) != noErr) {
        self.statusItemText.title = @"Could not read camera streams";
        return NO;
    }

    [streamData getBytes:&_cmioSinkStreamID range:NSMakeRange(sizeof(CMIOStreamID), sizeof(CMIOStreamID))];

    OSStatus status = CMIOStreamCopyBufferQueue(
        _cmioSinkStreamID,
        [](CMIOStreamID streamID, void *token, void *refCon) {
            (void) streamID;
            (void) token;
            (void) refCon;
        },
        NULL,
        &_cmioQueue);

    if (status != noErr || !_cmioQueue) {
        self.statusItemText.title = @"Could not open camera sink queue";
        return NO;
    }

    status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                            kPixelFormat,
                                            kFrameWidth,
                                            kFrameHeight,
                                            NULL,
                                            &_formatDescription);
    if (status != noErr || !_formatDescription) {
        self.statusItemText.title = @"Could not create video format";
        [self closeCMIOSink];
        return NO;
    }

    status = CMIODeviceStartStream(_cmioDeviceID, _cmioSinkStreamID);
    if (status != noErr) {
        self.statusItemText.title = @"Could not start camera sink";
        [self closeCMIOSink];
        return NO;
    }

    return YES;
}

- (CMIODeviceID)findCameraDeviceID
{
    UInt32 size = 0;
    UInt32 used = 0;
    CMIOObjectPropertyAddress address = {
        kCMIOHardwarePropertyDevices,
        kCMIOObjectPropertyScopeGlobal,
        kCMIOObjectPropertyElementMain,
    };

    if (CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject, &address, 0, NULL, &size) != noErr) {
        return 0;
    }

    NSMutableData *devices = [NSMutableData dataWithLength:size];
    if (CMIOObjectGetPropertyData(kCMIOObjectSystemObject, &address, 0, NULL, size, &used, devices.mutableBytes) != noErr) {
        return 0;
    }

    CFUUIDRef expectedUUID = CFUUIDCreateFromString(kCFAllocatorDefault, CFSTR(MAC_VIRTUAL_CAMERA_DEVICE_UUID));
    if (!expectedUUID) {
        return 0;
    }

    size_t deviceCount = size / sizeof(CMIOObjectID);

    for (size_t index = 0; index < deviceCount; index++) {
        CMIOObjectID deviceID = 0;
        [devices getBytes:&deviceID range:NSMakeRange(index * sizeof(CMIOObjectID), sizeof(CMIOObjectID))];

        address.mSelector = kCMIODevicePropertyDeviceUID;
        UInt32 uidSize = 0;
        if (CMIOObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &uidSize) != noErr) {
            continue;
        }

        CFStringRef uid = NULL;
        if (CMIOObjectGetPropertyData(deviceID, &address, 0, NULL, uidSize, &used, &uid) != noErr || !uid) {
            continue;
        }

        CFUUIDRef deviceUUID = CFUUIDCreateFromString(kCFAllocatorDefault, uid);
        BOOL match = deviceUUID && CFEqual(expectedUUID, deviceUUID);
        if (deviceUUID) {
            CFRelease(deviceUUID);
        }
        CFRelease(uid);

        if (match) {
            CFRelease(expectedUUID);
            return deviceID;
        }
    }

    CFRelease(expectedUUID);
    return 0;
}

- (void)startScreenCapture
{
    self.statusItemText.title = @"Starting screen capture...";

    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopVirtualCamera:nil];
                self.statusItemText.title = error.localizedDescription;
            });
            return;
        }

        SCDisplay *targetDisplay = nil;
        CGDirectDisplayID mainDisplayID = CGMainDisplayID();
        for (SCDisplay *display in content.displays) {
            if (display.displayID == mainDisplayID) {
                targetDisplay = display;
                break;
            }
        }

        if (!targetDisplay) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopVirtualCamera:nil];
                self.statusItemText.title = @"Main display unavailable";
            });
            return;
        }

        NSArray *emptyWindows = @[];
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:targetDisplay excludingWindows:emptyWindows];
        SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
        configuration.width = kFrameWidth;
        configuration.height = kFrameHeight;
        configuration.pixelFormat = kPixelFormat;
        configuration.minimumFrameInterval = CMTimeMake(1, kFrameRate);
        configuration.queueDepth = 8;
        configuration.showsCursor = YES;

        ScreenCaptureOutput *output = [[ScreenCaptureOutput alloc] init];
        output.owner = self;

        SCStream *stream = [[SCStream alloc] initWithFilter:filter configuration:configuration delegate:output];
        NSError *outputError = nil;
        if (![stream addStreamOutput:output type:SCStreamOutputTypeScreen sampleHandlerQueue:self->_screenQueue error:&outputError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopVirtualCamera:nil];
                self.statusItemText.title = outputError.localizedDescription ?: @"Could not attach screen output";
            });
            return;
        }

        self->_captureOutput = output;
        self->_screenStream = stream;
        [stream startCaptureWithCompletionHandler:^(NSError *startError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_screenStream != stream) {
                    return;
                }

                self->_starting = NO;
                if (startError) {
                    [self stopVirtualCamera:nil];
                    self.statusItemText.title = startError.localizedDescription;
                    return;
                }

                self->_running = YES;
                self.statusItemText.title = @"Virtual camera running: Screen";
                [self updateMenu];
            });
        }];
    }];
}

- (void)handleScreenSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    @synchronized(self) {
        if (!_running || !_screenStream) {
            return;
        }

        if (!_cmioQueue || !_formatDescription) {
            return;
        }

        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!imageBuffer) {
            return;
        }

        CMSampleTimingInfo timing = {};
        timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
        timing.duration = CMTimeMake(1, kFrameRate);
        timing.decodeTimeStamp = kCMTimeInvalid;

        CMSampleBufferRef outputBuffer = NULL;
        OSStatus status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                                             imageBuffer,
                                                             true,
                                                             NULL,
                                                             NULL,
                                                             _formatDescription,
                                                             &timing,
                                                             &outputBuffer);
        if (status != noErr || !outputBuffer) {
            return;
        }

        CMSimpleQueueEnqueue(_cmioQueue, outputBuffer);
    }
}

- (void)updateMenu
{
    self.startItem.enabled = !_starting && !_running;
    self.stopItem.enabled = _starting || _running;
    self.screenItem.state = NSControlStateValueOn;
}

@end

int main(int argc, char *argv[])
{
    (void) argc;
    (void) argv;

    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        MacVirtualCameraApp *delegate = [[MacVirtualCameraApp alloc] init];
        application.delegate = delegate;
        [application run];
    }

    return 0;
}
