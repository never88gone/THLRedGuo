void VideoOutput::SetSize(std::optional<int64_t> width,
                          std::optional<int64_t> height) {
  thread_pool_ref_->Post([this, width, height]() {
    if (destroyed_) return;
    width_ = width;
    height_ = height;
    if (pixel_buffer_ && width && height && *width > 0 && *height > 0) {
      const auto factor = (std::min)(1.0, (std::min)(
          static_cast<double>(SW_RENDERING_MAX_WIDTH) / *width,
          static_cast<double>(SW_RENDERING_MAX_HEIGHT) / *height));
      width_ = std::max<int64_t>(1, static_cast<int64_t>(*width * factor));
      height_ = std::max<int64_t>(1, static_cast<int64_t>(*height * factor));
    }
  });
}
