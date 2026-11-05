#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <iostream>
#include <memory>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <variant>

struct FlutterDesktopGpuSurfaceDescriptor {};
struct FlutterDesktopPixelBuffer {};
constexpr int kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle = 1;

namespace flutter {
struct GpuSurfaceTexture {
  using Callback = std::function<const FlutterDesktopGpuSurfaceDescriptor*(int, int)>;
  Callback callback;
  GpuSurfaceTexture(int, Callback value) : callback(std::move(value)) {}
};
struct PixelBufferTexture {
  using Callback = std::function<const FlutterDesktopPixelBuffer*(int, int)>;
  Callback callback;
  explicit PixelBufferTexture(Callback value) : callback(std::move(value)) {}
};
struct TextureVariant {
  std::variant<GpuSurfaceTexture, PixelBufferTexture> value;
  explicit TextureVariant(GpuSurfaceTexture texture) : value(std::move(texture)) {}
  explicit TextureVariant(PixelBufferTexture texture) : value(std::move(texture)) {}
};
}

struct Surface {
  int reads = 0;
  void Read() { ++reads; }
};

struct Output {
  std::mutex textures_mutex_;
  std::atomic<bool> destroyed_{false};
  std::atomic<int64_t> texture_id_{0};
  std::unordered_map<int64_t, std::unique_ptr<FlutterDesktopGpuSurfaceDescriptor>> textures_;
  std::unordered_map<int64_t, std::unique_ptr<FlutterDesktopPixelBuffer>> pixel_buffer_textures_;
  std::unique_ptr<Surface> surface_manager_ = std::make_unique<Surface>();
  std::shared_ptr<std::atomic<int64_t>> published;

  std::unique_ptr<flutter::TextureVariant> Gpu() {
#ifdef THL_NATIVE_BASELINE
#include "baseline_gpu_texture.inc"
    published = std::make_shared<std::atomic<int64_t>>(0);
#else
#include "../windows/runner/media_kit_gpu_texture.inc"
    published = published_id;
#endif
    return texture_variant;
  }

  std::unique_ptr<flutter::TextureVariant> Pixel() {
#include "../windows/runner/media_kit_pixel_texture.inc"
    published = published_id;
    return texture_variant;
  }
};

int main(int argc, char**) {
  Output gpu;
  auto gpuTexture = gpu.Gpu();
  auto& gpuRead = std::get<flutter::GpuSurfaceTexture>(gpuTexture->value).callback;
  if (argc > 1) {
    std::this_thread::sleep_for(std::chrono::seconds(4));
    gpu.texture_id_ = 1;
    gpuRead(1, 1);
    return 9;
  }
  if (gpuRead(1, 1) != nullptr) return 1;
  gpu.texture_id_ = 1;
  if (gpuRead(1, 1) != nullptr) return 2;
  gpu.published->store(1);
  if (gpuRead(1, 1) != nullptr) return 3;
  gpu.textures_[1] = std::make_unique<FlutterDesktopGpuSurfaceDescriptor>();
  if (!gpuRead(1, 1) || gpu.surface_manager_->reads != 1) return 4;
  gpu.texture_id_ = 2;
  if (gpuRead(1, 1) != nullptr) return 5;
  gpu.texture_id_ = 1;
  gpu.textures_.erase(1);
  if (gpuRead(1, 1) != nullptr) return 6;
  gpu.textures_[1] = std::make_unique<FlutterDesktopGpuSurfaceDescriptor>();
  gpu.destroyed_ = true;
  if (gpuRead(1, 1) != nullptr) return 7;

  Output pixel;
  auto pixelTexture = pixel.Pixel();
  auto& pixelRead = std::get<flutter::PixelBufferTexture>(pixelTexture->value).callback;
  if (pixelRead(1, 1) != nullptr) return 8;
  pixel.texture_id_ = 1;
  if (pixelRead(1, 1) != nullptr) return 9;
  pixel.published->store(1);
  if (pixelRead(1, 1) != nullptr) return 10;
  pixel.pixel_buffer_textures_[1] = std::make_unique<FlutterDesktopPixelBuffer>();
  if (!pixelRead(1, 1)) return 11;
  pixel.texture_id_ = 2;
  if (pixelRead(1, 1) != nullptr) return 12;
  pixel.texture_id_ = 1;
  pixel.pixel_buffer_textures_.erase(1);
  if (pixelRead(1, 1) != nullptr) return 13;
  pixel.pixel_buffer_textures_[1] = std::make_unique<FlutterDesktopPixelBuffer>();
  pixel.destroyed_ = true;
  if (pixelRead(1, 1) != nullptr) return 14;
  std::cout << "14 native texture publication, resize, retirement and destruction checks passed" << std::endl;
  return 0;
}
