#include "facebetter_processor.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>
#include <windows.h>

#ifdef MOONFIN_FACEBETTER
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <vector>
#ifdef _MSC_VER
// The SDK exports ImageFrame with a private std::shared_ptr member. Its DLL
// interface warning is owned by the vendor; keep /WX for Moonfin's code.
#pragma warning(push)
#pragma warning(disable : 4251)
#endif
#include <facebetter/beauty_effect_engine.h>
#include <facebetter/beauty_params.h>
#include <facebetter/image_frame.h>
#ifdef _MSC_VER
#pragma warning(pop)
#endif
#include "facebetter_config.h"
#endif

namespace {
#ifdef MOONFIN_FACEBETTER
// The bundled ANGLE SDK ships GLES2 headers. These ES3 state tokens are
// queried only after the current context reports OpenGL ES 3 support;
// all functions used here are already part of the GLES2 API.
constexpr GLenum kPixelPackBuffer = 0x88EB;
constexpr GLenum kPixelUnpackBuffer = 0x88EC;
constexpr GLenum kPixelPackBufferBinding = 0x88ED;
constexpr GLenum kPixelUnpackBufferBinding = 0x88EF;
constexpr GLenum kPackRowLength = 0x0D02;
constexpr GLenum kPackSkipRows = 0x0D03;
constexpr GLenum kPackSkipPixels = 0x0D04;
constexpr GLenum kUnpackRowLength = 0x0CF2;
constexpr GLenum kUnpackSkipRows = 0x0CF3;
constexpr GLenum kUnpackSkipPixels = 0x0CF4;
#endif
using flutter::EncodableMap;
using flutter::EncodableValue;
struct Settings {
  bool enabled = false;
  int64_t handle = 0;
  float values[6] = {};
  uint64_t revision = 0;
  uint64_t epoch = 0;
  std::string bypass;
#ifdef MOONFIN_FACEBETTER
  std::string token = FACEBETTER_LICENSE_TOKEN;
  std::string app_id = FACEBETTER_APP_ID;
  std::string app_key = FACEBETTER_APP_KEY;
#else
  std::string token, app_id, app_key;
#endif
};
std::mutex state_mutex;
Settings settings;
std::string status = "waiting";
bool ConfiguredUnlocked() {
#ifdef MOONFIN_FACEBETTER
  return !settings.token.empty() || (!settings.app_id.empty() && !settings.app_key.empty());
#else
  return false;
#endif
}
float Strength(const EncodableMap& args, const char* name) {
  auto it = args.find(EncodableValue(name));
  if (it == args.end()) return 0;
  double value = 0;
  if (auto d = std::get_if<double>(&it->second)) value = *d;
  else if (auto i = std::get_if<int32_t>(&it->second)) value = *i;
  return std::isfinite(value) ? static_cast<float>(std::clamp(value, 0.0, 1.0)) : 0;
}
#ifdef MOONFIN_FACEBETTER
void SetStatus(int64_t handle, const std::string& value) {
  std::lock_guard<std::mutex> lock(state_mutex);
  if (settings.handle == handle && settings.enabled) status = value;
}
std::string Property(mpv_handle* handle, const char* name) {
  char* value = mpv_get_property_string(handle, name);
  std::string result = value ? value : "";
  mpv_free(value);
  return result;
}
#endif
}  // namespace

struct FacebetterProcessor::Impl {
#ifdef MOONFIN_FACEBETTER
  std::shared_ptr<facebetter::BeautyEffectEngine> engine;
  struct Events { std::atomic<int> initialization{0}; };
  std::shared_ptr<Events> events = std::make_shared<Events>();
  std::chrono::steady_clock::time_point started;
  uint64_t revision = 0;
  uint64_t epoch = ~uint64_t{0};
  bool basic_only = false;
  bool failed = false;
  std::vector<uint8_t> rgba;
  GLuint program = 0, texture = 0, vertices = 0;
#endif
};

FacebetterProcessor::FacebetterProcessor() : impl_(std::make_unique<Impl>()) {}
FacebetterProcessor::~FacebetterProcessor() = default;

bool FacebetterProcessor::Configured() {
  std::lock_guard<std::mutex> lock(state_mutex);
  return ConfiguredUnlocked();
}

void FacebetterProcessor::ReleaseGL() {
#ifdef MOONFIN_FACEBETTER
  if (impl_->program) glDeleteProgram(impl_->program);
  if (impl_->texture) glDeleteTextures(1, &impl_->texture);
  if (impl_->vertices) glDeleteBuffers(1, &impl_->vertices);
  impl_->program = impl_->texture = impl_->vertices = 0;
#endif
}

void FacebetterProcessor::ProcessGL(mpv_handle* handle, int width, int height) {
#ifdef MOONFIN_FACEBETTER
  const auto id = reinterpret_cast<int64_t>(handle);
  {
    std::lock_guard<std::mutex> lock(state_mutex);
    if (!settings.enabled || settings.handle != id || !ConfiguredUnlocked()) return;
  }
  if (width <= 0 || height <= 0) return;
  if (std::max(width, height) > 1920 || std::min(width, height) > 1080) {
    SetStatus(id, "bypassResolution"); return;
  }
  // Read the actual rendered frame, before ANGLE publishes its D3D texture.
  // No screenshot command, secondary player, timer or presentation overlay.
  const auto* version = glGetString(GL_VERSION);
  const bool es3 = version && std::string(reinterpret_cast<const char*>(version)).find("OpenGL ES 3") != std::string::npos;
  GLint old_fbo = 0, pack = 0, pack_buffer = 0, pack_row = 0, pack_rows = 0, pack_pixels = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &old_fbo);
  glGetIntegerv(GL_PACK_ALIGNMENT, &pack);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  if (es3) {
    glGetIntegerv(kPixelPackBufferBinding, &pack_buffer);
    glGetIntegerv(kPackRowLength, &pack_row);
    glGetIntegerv(kPackSkipRows, &pack_rows);
    glGetIntegerv(kPackSkipPixels, &pack_pixels);
    glBindBuffer(kPixelPackBuffer, 0);
    glPixelStorei(kPackRowLength, 0);
    glPixelStorei(kPackSkipRows, 0);
    glPixelStorei(kPackSkipPixels, 0);
  }
  impl_->rgba.resize(static_cast<size_t>(width) * height * 4);
  glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, impl_->rgba.data());
  const auto read_error = glGetError();
  if (es3) {
    glBindBuffer(kPixelPackBuffer, pack_buffer);
    glPixelStorei(kPackRowLength, pack_row);
    glPixelStorei(kPackSkipRows, pack_rows);
    glPixelStorei(kPackSkipPixels, pack_pixels);
  }
  glPixelStorei(GL_PACK_ALIGNMENT, pack);
  glBindFramebuffer(GL_FRAMEBUFFER, old_fbo);
  if (read_error != GL_NO_ERROR) { SetStatus(id, "failed"); return; }
  // The SDK receives top-to-bottom CPU rows; GL readback starts at the bottom.
  for (int row = 0; row < height / 2; ++row) {
    auto first = impl_->rgba.begin() + static_cast<size_t>(row) * width * 4;
    auto other = impl_->rgba.begin() + static_cast<size_t>(height - row - 1) * width * 4;
    std::swap_ranges(first, first + width * 4, other);
  }
  const auto display = eglGetCurrentDisplay();
  const auto context = eglGetCurrentContext();
  const auto draw = eglGetCurrentSurface(EGL_DRAW), read = eglGetCurrentSurface(EGL_READ);
  const bool processed = Process(handle, impl_->rgba.data(), width, height);
  // Facebetter owns a different GL context. Restore ANGLE explicitly before
  // touching mpv's presentation surface, including on an initialization failure.
  if (eglMakeCurrent(display, draw, read, context) != EGL_TRUE) {
    SetStatus(id, "failed"); return;
  }
  if (!processed) return;

  GLint old_program, old_array, old_active, old_texture, unpack, viewport[4];
  GLint unpack_buffer = 0, unpack_row = 0, unpack_rows = 0, unpack_pixels = 0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &old_program);
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &old_array);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &old_active);
  glActiveTexture(GL_TEXTURE0);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &old_texture);
  glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpack);
  if (es3) {
    glGetIntegerv(kPixelUnpackBufferBinding, &unpack_buffer);
    glGetIntegerv(kUnpackRowLength, &unpack_row);
    glGetIntegerv(kUnpackSkipRows, &unpack_rows);
    glGetIntegerv(kUnpackSkipPixels, &unpack_pixels);
    glBindBuffer(kPixelUnpackBuffer, 0);
    glPixelStorei(kUnpackRowLength, 0);
    glPixelStorei(kUnpackSkipRows, 0);
    glPixelStorei(kUnpackSkipPixels, 0);
  }
  glGetIntegerv(GL_VIEWPORT, viewport);
  GLboolean color_mask[4];
  glGetBooleanv(GL_COLOR_WRITEMASK, color_mask);
  const GLenum capabilities[] = {GL_BLEND, GL_SCISSOR_TEST, GL_DEPTH_TEST, GL_STENCIL_TEST, GL_CULL_FACE};
  GLboolean enabled[5];
  for (int i = 0; i < 5; ++i) { enabled[i] = glIsEnabled(capabilities[i]); glDisable(capabilities[i]); }
  struct Attribute { GLint enabled, size, type, normalized, stride, buffer; void* pointer; } attributes[2];
  for (GLuint i = 0; i < 2; ++i) {
    auto& a = attributes[i];
    glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &a.enabled);
    glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_SIZE, &a.size);
    glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_TYPE, &a.type);
    glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_NORMALIZED, &a.normalized);
    glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_STRIDE, &a.stride);
    glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, &a.buffer);
    glGetVertexAttribPointerv(i, GL_VERTEX_ATTRIB_ARRAY_POINTER, &a.pointer);
  }
  if (!impl_->program) {
    const char* vertex = "attribute vec2 aPosition; attribute vec2 aTexCoord; varying vec2 uv; void main(){uv=aTexCoord;gl_Position=vec4(aPosition,0.0,1.0);}";
    const char* fragment = "precision mediump float; varying vec2 uv; uniform sampler2D image; void main(){gl_FragColor=vec4(texture2D(image,uv).rgb,1.0);}";
    const auto vs = glCreateShader(GL_VERTEX_SHADER), fs = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(vs, 1, &vertex, nullptr); glCompileShader(vs);
    glShaderSource(fs, 1, &fragment, nullptr); glCompileShader(fs);
    impl_->program = glCreateProgram();
    glAttachShader(impl_->program, vs); glAttachShader(impl_->program, fs);
    glBindAttribLocation(impl_->program, 0, "aPosition");
    glBindAttribLocation(impl_->program, 1, "aTexCoord");
    glLinkProgram(impl_->program);
    glDeleteShader(vs); glDeleteShader(fs);
    glGenTextures(1, &impl_->texture);
    glGenBuffers(1, &impl_->vertices);
  }
  GLint linked = GL_FALSE;
  glGetProgramiv(impl_->program, GL_LINK_STATUS, &linked);
  if (linked == GL_TRUE) {
    const GLfloat vertices[] = {-1,-1,0,1, 1,-1,1,1, -1,1,0,0, 1,1,1,0};
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(0, 0, width, height);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glUseProgram(impl_->program);
    glBindTexture(GL_TEXTURE_2D, impl_->texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, impl_->rgba.data());
    glUniform1i(glGetUniformLocation(impl_->program, "image"), 0);
    glBindBuffer(GL_ARRAY_BUFFER, impl_->vertices);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), nullptr);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), reinterpret_cast<void*>(2 * sizeof(GLfloat)));
    glEnableVertexAttribArray(0); glEnableVertexAttribArray(1);
    if (glGetError() == GL_NO_ERROR) glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    else SetStatus(id, "failed");
  } else { SetStatus(id, "failed"); }
  for (GLuint i = 0; i < 2; ++i) {
    const auto& a = attributes[i];
    glBindBuffer(GL_ARRAY_BUFFER, a.buffer);
    glVertexAttribPointer(i, a.size, a.type, static_cast<GLboolean>(a.normalized), a.stride, a.pointer);
    if (a.enabled) glEnableVertexAttribArray(i); else glDisableVertexAttribArray(i);
  }
  glBindBuffer(GL_ARRAY_BUFFER, old_array);
  glBindFramebuffer(GL_FRAMEBUFFER, old_fbo);
  glUseProgram(old_program);
  glBindTexture(GL_TEXTURE_2D, old_texture);
  glActiveTexture(old_active);
  glPixelStorei(GL_UNPACK_ALIGNMENT, unpack);
  if (es3) {
    glBindBuffer(kPixelUnpackBuffer, unpack_buffer);
    glPixelStorei(kUnpackRowLength, unpack_row);
    glPixelStorei(kUnpackSkipRows, unpack_rows);
    glPixelStorei(kUnpackSkipPixels, unpack_pixels);
  }
  glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
  glColorMask(color_mask[0], color_mask[1], color_mask[2], color_mask[3]);
  for (int i = 0; i < 5; ++i) if (enabled[i]) glEnable(capabilities[i]);
#else
  (void)handle; (void)width; (void)height;
#endif
}

EncodableMap FacebetterProcessor::Configure(const EncodableMap& args) {
  {
    std::lock_guard<std::mutex> lock(state_mutex);
    auto license = args.find(EncodableValue("license"));
    if (license != args.end()) {
      if (const auto* map = std::get_if<EncodableMap>(&license->second)) {
        auto text = [&](const char* key) {
          auto value = map->find(EncodableValue(key));
          return value != map->end() && std::holds_alternative<std::string>(value->second)
              ? std::get<std::string>(value->second) : std::string();
        };
        const auto token = text("licenseToken"), app_id = text("appId"), app_key = text("appKey");
        if (token != settings.token || app_id != settings.app_id || app_key != settings.app_key) {
          settings.token = token; settings.app_id = app_id; settings.app_key = app_key;
          ++settings.epoch;
          status = "waiting";
        }
      }
    }
    auto enabled = args.find(EncodableValue("enabled"));
    bool was_enabled = settings.enabled;
    settings.enabled = enabled != args.end() &&
        std::holds_alternative<bool>(enabled->second) && std::get<bool>(enabled->second);
    if (was_enabled != settings.enabled) ++settings.epoch;
    auto bypass = args.find(EncodableValue("bypassStatus"));
    settings.bypass = bypass != args.end() && std::holds_alternative<std::string>(bypass->second)
        ? std::get<std::string>(bypass->second) : "";
    const auto previous_handle = settings.handle;
    auto handle = args.find(EncodableValue("handle"));
    if (handle != args.end()) {
      if (auto h = std::get_if<int64_t>(&handle->second)) settings.handle = *h;
      else if (auto h32 = std::get_if<int32_t>(&handle->second)) settings.handle = *h32;
    }
    if (previous_handle != settings.handle) { ++settings.epoch; status = "waiting"; }
    const char* names[] = {"smoothing", "whitening", "rosiness", "sharpening", "faceThin", "eyeSize"};
    bool changed = was_enabled != settings.enabled;
    for (int i = 0; i < 6; ++i) {
      float value = Strength(args, names[i]);
      changed = changed || value != settings.values[i];
      settings.values[i] = value;
    }
    if (changed) ++settings.revision;
    if (!settings.enabled) status = "disabled";
    else if (!ConfiguredUnlocked()) {
#ifdef MOONFIN_FACEBETTER
      status = "missingLicense";
#else
      status = "missingSdk";
#endif
    } else if (!was_enabled) status = "waiting";
  }
  return Status();
}

EncodableMap FacebetterProcessor::Status() {
  std::lock_guard<std::mutex> lock(state_mutex);
  const auto visible_status = settings.enabled && ConfiguredUnlocked() && !settings.bypass.empty()
      ? settings.bypass : status;
  return {{EncodableValue("status"), EncodableValue(visible_status)},
          {EncodableValue("configured"), EncodableValue(ConfiguredUnlocked())}};
}

bool FacebetterProcessor::Process(mpv_handle* handle, uint8_t* rgba, int width, int height) {
#ifdef MOONFIN_FACEBETTER
  Settings current;
  {
    std::lock_guard<std::mutex> lock(state_mutex);
    current = settings;
  }
  auto id = reinterpret_cast<int64_t>(handle);
  if (!current.enabled || current.handle != id) {
    impl_->engine.reset();
    impl_->failed = false;
    impl_->events = std::make_shared<Impl::Events>();
    return false;
  }
  if (!Configured()) return false;
  if (impl_->epoch != current.epoch) {
    impl_->engine.reset();
    impl_->failed = false;
    impl_->events = std::make_shared<Impl::Events>();
    impl_->epoch = current.epoch;
  }
  const auto gamma = Property(handle, "video-params/gamma");
  const auto primaries = Property(handle, "video-params/primaries");
  const auto dv = Property(handle, "video-params/dolby-vision-profile");
  if (gamma == "pq" || gamma == "hlg" || gamma == "st428" ||
      primaries == "bt.2020" || (!dv.empty() && dv != "0")) {
    SetStatus(id, "bypassHdr"); return false;
  }
  int64_t source_w = 0, source_h = 0;
  mpv_get_property(handle, "video-params/w", MPV_FORMAT_INT64, &source_w);
  mpv_get_property(handle, "video-params/h", MPV_FORMAT_INT64, &source_h);
  if (source_w <= 0 || source_h <= 0) { SetStatus(id, "waiting"); return false; }
  auto long_side = std::max(source_w, source_h), short_side = std::min(source_w, source_h);
  if (long_side > 1920 || short_side > 1080) { SetStatus(id, "bypassResolution"); return false; }
  double fps = 0;
  mpv_get_property(handle, "container-fps", MPV_FORMAT_DOUBLE, &fps);
  if (!std::isfinite(fps) || fps <= 0) { SetStatus(id, "waiting"); return false; }
  if (fps > 60.1 || (fps > 30.1 && (long_side > 1280 || short_side > 720))) {
    SetStatus(id, "bypassFrameRate"); return false;
  }
  if (impl_->failed) { SetStatus(id, "failed"); return false; }
  try {
    if (!impl_->engine) {
      facebetter::EngineConfig config;
      config.license_token = current.token;
      config.app_id = current.app_id;
      config.app_key = current.app_key;
      wchar_t exe[32768];
      const auto length = GetModuleFileNameW(nullptr, exe, 32768);
      auto resource = std::filesystem::path(std::wstring(exe, length)).parent_path() / "resource.fbd";
      if (!std::filesystem::exists(resource)) { SetStatus(id, "missingResources"); return false; }
      config.resource_path = resource.parent_path().u8string();
      config.external_context = false;
      impl_->engine = facebetter::BeautyEffectEngine::Create(config);
      if (!impl_->engine) { impl_->failed = true; SetStatus(id, "failed"); return false; }
      facebetter::EngineCallbacks callbacks;
      auto events = impl_->events;
      callbacks.on_engine_event = [events](int code, const std::string&) {
        if (code == 100) {
          int expected = 0;
          events->initialization.compare_exchange_strong(expected, 1);
        }
        else if (code == 1 || code == 101) events->initialization.store(-1);
      };
      impl_->engine->SetCallbacks(callbacks);
      impl_->started = std::chrono::steady_clock::now();
      impl_->revision = ~current.revision;
    }
    if (impl_->events->initialization.load() == 1 && impl_->revision != current.revision) {
      auto& engine = impl_->engine;
      engine->SetBeautySkinOnly(true);
      engine->SetSmoothing(current.values[0]);
      engine->SetWhitening(current.values[1]);
      engine->SetRosiness(current.values[2]);
      engine->SetSharpening(current.values[3]);
      int face = engine->SetReshape(facebetter::beauty_params::Reshape::FaceThin, current.values[4]);
      int eyes = engine->SetReshape(facebetter::beauty_params::Reshape::EyeSize, current.values[5]);
      impl_->basic_only = (face != 0 && current.values[4] > 0) || (eyes != 0 && current.values[5] > 0);
      impl_->revision = current.revision;
    }
    // ProcessImage drives initialization too. Do not publish its output until
    // the SDK confirms both resources and authorization are ready.
    auto input = facebetter::ImageFrame::CreateWithRGBA(rgba, width, height, width * 4);
    if (!input) { SetStatus(id, "failed"); return false; }
    input->type = facebetter::FrameType::Video;
    auto output = impl_->engine->ProcessImage(input);
    const int initialized = impl_->events->initialization.load();
    if (initialized < 0 || (initialized == 0 && std::chrono::steady_clock::now() - impl_->started > std::chrono::seconds(15))) {
      impl_->failed = true; SetStatus(id, "failed"); return false;
    }
    if (initialized == 0 || impl_->revision != current.revision) { SetStatus(id, "initializing"); return false; }
    auto converted = output ? output->Convert(facebetter::Format::RGBA) : nullptr;
    if (!converted || converted->Width() != width || converted->Height() != height ||
        converted->Stride() < width * 4 || !converted->Data()) {
      SetStatus(id, "failed"); return false;
    }
    for (int y = 0; y < height; ++y)
      std::memcpy(rgba + y * width * 4, converted->Data() + y * converted->Stride(), width * 4);
    SetStatus(id, impl_->basic_only ? "readyBasicOnly" : "ready");
    return true;
  } catch (...) { impl_->failed = true; SetStatus(id, "failed"); return false; }
#else
  (void)handle; (void)rgba; (void)width; (void)height;
  return false;
#endif
}
