void VideoOutputManager::Create(
    int64_t handle, VideoOutputConfiguration configuration,
    std::function<void(int64_t, int64_t, int64_t)> texture_update_callback) {
  operations_->Post([this, handle, configuration, texture_update_callback]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) == video_outputs_.end()) {
      auto instance = std::make_unique<VideoOutput>(
          handle, configuration, registrar_, thread_pool_.get());
      instance->SetTextureUpdateCallback(texture_update_callback);
      video_outputs_.insert(std::make_pair(handle, std::move(instance)));
    }
  });
}

void VideoOutputManager::SetSize(int64_t handle,
                               std::optional<int64_t> width,
                               std::optional<int64_t> height) {
  operations_->Post([this, handle, width, height]() {
    std::lock_guard<std::mutex> lock(mutex_);
    auto output = video_outputs_.find(handle);
    if (output != video_outputs_.end()) output->second->SetSize(width, height);
  });
}

void VideoOutputManager::Dispose(int64_t handle, std::function<void()> completed) {
  operations_->Post([this, handle, completed]() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      video_outputs_.erase(handle);
    }
    completed();
  });
}

VideoOutputManager::~VideoOutputManager() {
  operations_.reset();
  std::lock_guard<std::mutex> lock(mutex_);
  video_outputs_.clear();
}
