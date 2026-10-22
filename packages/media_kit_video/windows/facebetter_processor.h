#pragma once

#include <flutter/encodable_value.h>
#include <mpv/client.h>
#include <memory>

// Settings are published on the platform thread; each output owns its engine
// exclusively on media_kit's render worker. Preview outputs are never selected.
class FacebetterProcessor {
 public:
  FacebetterProcessor();
  ~FacebetterProcessor();
  static bool Configured();
  static flutter::EncodableMap Configure(const flutter::EncodableMap& args);
  static flutter::EncodableMap Status();
  bool Process(mpv_handle* handle, uint8_t* rgba, int width, int height);
  void ProcessGL(mpv_handle* handle, int width, int height);
  void ReleaseGL();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
