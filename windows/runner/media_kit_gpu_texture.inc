    auto published_id = std::make_shared<std::atomic<int64_t>>(0);
    auto texture_variant = std::make_unique<flutter::TextureVariant>(
        flutter::GpuSurfaceTexture(kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
            [this, published_id](auto, auto) -> const FlutterDesktopGpuSurfaceDescriptor* {
              std::lock_guard<std::mutex> lock(textures_mutex_);
              const auto id = published_id->load();
              if (destroyed_ || !id || id != texture_id_.load()) return nullptr;
              const auto texture = textures_.find(id);
              if (texture == textures_.end()) return nullptr;
              surface_manager_->Read();
              return texture->second.get();
            }));
