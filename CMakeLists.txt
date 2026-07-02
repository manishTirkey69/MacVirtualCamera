cmake_minimum_required(VERSION 3.28...3.30)

set(CMAKE_OSX_DEPLOYMENT_TARGET 13.0 CACHE STRING "Minimum macOS deployment target")

project(MacVirtualCamera LANGUAGES C CXX OBJCXX Swift)

if(NOT APPLE)
  message(FATAL_ERROR "MacVirtualCamera is a macOS-only standalone app.")
endif()

set(MAC_VIRTUAL_CAMERA_APP_ID
    "com.obsproject.MacVirtualCamera"
    CACHE STRING "macOS app bundle identifier"
)
set(MAC_VIRTUAL_CAMERA_EXTENSION_ID
    "com.obsproject.MacVirtualCamera.CameraExtension"
    CACHE STRING "macOS camera extension bundle identifier"
)
set(MAC_VIRTUAL_CAMERA_DEVICE_UUID
    "7E3F37E2-5F41-44B4-9B73-0B98F3D66E91"
    CACHE STRING "Stable CMIO virtual camera device UUID"
)
set(MAC_VIRTUAL_CAMERA_SOURCE_UUID
    "54F52CF6-9A7A-4FA1-A5F7-096E79D12032"
    CACHE STRING "Stable CMIO virtual camera source stream UUID"
)
set(MAC_VIRTUAL_CAMERA_SINK_UUID
    "8C8600E7-46BB-44C9-8C1F-F91A5656B584"
    CACHE STRING "Stable CMIO virtual camera sink stream UUID"
)
set(MAC_VIRTUAL_CAMERA_DEVELOPMENT_TEAM
    ""
    CACHE STRING "Optional Apple development team ID for signing the app and system extension"
)

find_library(COCOA_LIBRARY Cocoa REQUIRED)
find_library(COREGRAPHICS_LIBRARY CoreGraphics REQUIRED)
find_library(COREMEDIA_LIBRARY CoreMedia REQUIRED)
find_library(COREMEDIAIO_LIBRARY CoreMediaIO REQUIRED)
find_library(COREVIDEO_LIBRARY CoreVideo REQUIRED)
find_library(SCREENCAPTUREKIT_LIBRARY ScreenCaptureKit REQUIRED)
find_library(SYSTEMEXTENSIONS_LIBRARY SystemExtensions REQUIRED)

add_executable(MacVirtualCamera MACOSX_BUNDLE)
target_sources(MacVirtualCamera PRIVATE src/MacVirtualCamera.mm)
target_compile_features(MacVirtualCamera PRIVATE cxx_std_17)
target_compile_options(MacVirtualCamera PRIVATE -fobjc-arc)
target_compile_definitions(
  MacVirtualCamera PRIVATE
  MAC_VIRTUAL_CAMERA_EXTENSION_ID="${MAC_VIRTUAL_CAMERA_EXTENSION_ID}"
  MAC_VIRTUAL_CAMERA_DEVICE_UUID="${MAC_VIRTUAL_CAMERA_DEVICE_UUID}"
)
target_link_libraries(
  MacVirtualCamera
  PRIVATE
    "${COCOA_LIBRARY}"
    "${COREGRAPHICS_LIBRARY}"
    "${COREMEDIA_LIBRARY}"
    "${COREMEDIAIO_LIBRARY}"
    "${COREVIDEO_LIBRARY}"
    "${SCREENCAPTUREKIT_LIBRARY}"
    "${SYSTEMEXTENSIONS_LIBRARY}"
)
set_target_properties(
  MacVirtualCamera
  PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/cmake/AppInfo.plist.in"
             XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${MAC_VIRTUAL_CAMERA_APP_ID}"
             XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
             XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/AppEntitlements.plist"
             XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME YES
)

add_executable(MacVirtualCameraCameraExtension MACOSX_BUNDLE)
target_sources(
  MacVirtualCameraCameraExtension
  PRIVATE
    extension/main.swift
    extension/CameraDeviceSource.swift
    extension/CameraProviderSource.swift
    extension/CameraStreamSink.swift
    extension/CameraStreamSource.swift
)
set_target_properties(
  MacVirtualCameraCameraExtension
  PROPERTIES OUTPUT_NAME "${MAC_VIRTUAL_CAMERA_EXTENSION_ID}"
             BUNDLE_EXTENSION systemextension
             MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/extension/Info.plist.in"
             XCODE_PRODUCT_TYPE com.apple.product-type.system-extension
             XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${MAC_VIRTUAL_CAMERA_EXTENSION_ID}"
             XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
             XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/extension/Entitlements.plist"
             XCODE_ATTRIBUTE_SWIFT_VERSION 5.0
             XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME YES
)

if(MAC_VIRTUAL_CAMERA_DEVELOPMENT_TEAM)
  set_target_properties(
    MacVirtualCamera MacVirtualCameraCameraExtension
    PROPERTIES XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${MAC_VIRTUAL_CAMERA_DEVELOPMENT_TEAM}"
  )
endif()

add_custom_command(
  TARGET MacVirtualCamera
  POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E make_directory
          "$<TARGET_BUNDLE_CONTENT_DIR:MacVirtualCamera>/Library/SystemExtensions"
  COMMAND "${CMAKE_COMMAND}" -E copy_directory
          "$<TARGET_BUNDLE_DIR:MacVirtualCameraCameraExtension>"
          "$<TARGET_BUNDLE_CONTENT_DIR:MacVirtualCamera>/Library/SystemExtensions/$<TARGET_BUNDLE_DIR_NAME:MacVirtualCameraCameraExtension>"
  VERBATIM
)

add_dependencies(MacVirtualCamera MacVirtualCameraCameraExtension)
