# MacVirtualCamera

Standalone macOS menu-bar app that exposes the main display as a virtual camera.

This app does not require OBS to be installed or running. It uses:

- ScreenCaptureKit for screen capture
- CoreMediaIO Camera Extension for the virtual camera device
- a status-bar menu for `Start Virtual Camera`, `Stop Virtual Camera`, and `Source Selection -> Screen`

## Requirements

- macOS 13 or newer
- code signing that allows installing a System Extension
- Screen Recording permission for `MacVirtualCamera.app`
- approval of the bundled Camera Extension in System Settings when macOS prompts for it

## Full Steps To Build And Run

From the `obs-studio` repo root:

```sh
cd /Users/manishtirkey/Documents/Github/obs-studio
```

1. Build with your Apple Developer Team ID.

Replace `YOURTEAMID` with your real Apple Developer Team ID:

```sh
cmake -S MacVirtualCamera -B build-mac-virtual-camera -G Xcode \
  -DMAC_VIRTUAL_CAMERA_DEVELOPMENT_TEAM=YOURTEAMID

cmake --build build-mac-virtual-camera --config Debug
```

2. Run the app:

```sh
open build-mac-virtual-camera/Debug/MacVirtualCamera.app
```

3. Approve macOS prompts.

macOS may ask you to approve:

- the bundled Camera Extension
- Screen Recording permission for `MacVirtualCamera.app`

If you grant Screen Recording permission, quit and reopen the app:

```sh
open build-mac-virtual-camera/Debug/MacVirtualCamera.app
```

4. Start the virtual camera from the menu bar.

Click `Mac VCam` in the macOS menu bar, then choose:

```text
Start Virtual Camera
```

The selected source is:

```text
Source Selection -> Screen
```

5. Select the camera in another app.

Open Zoom, Google Meet, Teams, Discord, OBS, or another camera app and select:

```text
Mac Virtual Camera
```

6. Stop the virtual camera from the menu bar:

```text
Stop Virtual Camera
```

## Build Only

Unsigned builds are useful for compiler checks, but macOS will not properly activate the camera system extension without valid signing and user approval:

```sh
cmake -S MacVirtualCamera -B build-mac-virtual-camera -G Xcode \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO

cmake --build build-mac-virtual-camera --config Debug
```

## Runtime

Launch `MacVirtualCamera.app`, approve the Camera Extension if prompted, then use the menu-bar item:

- `Start Virtual Camera` begins streaming the main screen to the virtual camera.
- `Stop Virtual Camera` stops capture and the virtual camera sink.
- `Source Selection -> Screen` is the active source.

The virtual camera appears to camera clients as `Mac Virtual Camera`.
