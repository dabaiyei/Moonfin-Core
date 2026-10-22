# The root is the Flutter Windows project even when this plugin is reached
# through Flutter's ephemeral plugin symlink.
set(FACEBETTER_SDK_DIR "${CMAKE_SOURCE_DIR}/facebetter-sdk" CACHE PATH "Facebetter Windows x64 SDK 2.1.1")
set(FACEBETTER_LICENSE_TOKEN "")
set(FACEBETTER_APP_ID "")
set(FACEBETTER_APP_KEY "")
if(EXISTS "${CMAKE_SOURCE_DIR}/facebetter.local.cmake")
  include("${CMAKE_SOURCE_DIR}/facebetter.local.cmake")
endif()
if(TARGET media_kit_video_plugin AND MEDIA_KIT_LIBS_AVAILABLE
   AND NOT CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|arm64|aarch64"
   AND NOT CMAKE_GENERATOR_PLATFORM MATCHES "ARM64|arm64"
   AND EXISTS "${FACEBETTER_SDK_DIR}/include/facebetter/beauty_effect_engine.h")
  foreach(asset lib/facebetter.lib lib/facebetter.dll resource/resource.fbd)
    if(NOT EXISTS "${FACEBETTER_SDK_DIR}/${asset}")
      message(FATAL_ERROR "Incomplete Facebetter SDK: ${asset}")
    endif()
  endforeach()
  configure_file("${CMAKE_CURRENT_LIST_DIR}/facebetter_config.h.in" "${CMAKE_CURRENT_BINARY_DIR}/facebetter_config.h" @ONLY)
  target_compile_definitions(media_kit_video_plugin PRIVATE MOONFIN_FACEBETTER=1)
  target_include_directories(media_kit_video_plugin PRIVATE "${FACEBETTER_SDK_DIR}/include" "${CMAKE_CURRENT_BINARY_DIR}")
  target_link_libraries(media_kit_video_plugin PRIVATE "${FACEBETTER_SDK_DIR}/lib/facebetter.lib")
  # Flutter installs bundled libraries beside the executable. The SDK expects
  # the base resource pack there too, at the absolute path passed by the host.
  set(media_kit_video_bundled_libraries
    "${FACEBETTER_SDK_DIR}/lib/facebetter.dll"
    "${FACEBETTER_SDK_DIR}/resource/resource.fbd"
    PARENT_SCOPE)
endif()
