    auto published_id = std::make_shared<std::atomic<int64_t>>(0);
    auto texture_variant = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture(
            [this, published_id](auto, auto) -> const FlutterDesktopPixelBuffer* {
              std::lock_guard<std::mutex> lock(textures_mutex_);
              const auto id = published_id->load();
              if (destroyed_ || !id || id != texture_id_.load()) return nullptr;
              const auto texture = pixel_buffer_textures_.find(id);
              return texture == pixel_buffer_textures_.end() ? nullptr : texture->second.get();
            }));
