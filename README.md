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

## Build

```sh
cmake -S MacVirtualCamera -B build-mac-virtual-camera -G Xcode
cmake --build build-mac-virtual-camera --config Debug
```

For a runnable build, sign with a valid Apple development team:

```sh
cmake -S MacVirtualCamera -B build-mac-virtual-camera -G Xcode \
  -DMAC_VIRTUAL_CAMERA_DEVELOPMENT_TEAM=YOURTEAMID
cmake --build build-mac-virtual-camera --config Debug
```

System Extensions require signing and user approval. An unsigned build can compile for development checks, but it will not activate the camera extension.

## Runtime

Launch `MacVirtualCamera.app`, approve the Camera Extension if prompted, then use the menu-bar item:

- `Start Virtual Camera` begins streaming the main screen to the virtual camera.
- `Stop Virtual Camera` stops capture and the virtual camera sink.
- `Source Selection -> Screen` is the active source.

The virtual camera appears to camera clients as `Mac Virtual Camera`.
