void VideoOutput::RetireTexture(int64_t id) {
  if (!id) return;
  {
    std::lock_guard<std::mutex> lock(retirement_mutex_);
    ++pending_retirements_;
  }
  registrar_->texture_registrar()->UnregisterTexture(id, [this, id]() {
    {
      std::lock_guard<std::mutex> lock(textures_mutex_);
      texture_variants_.erase(id);
      textures_.erase(id);
      pixel_buffer_textures_.erase(id);
    }
    std::lock_guard<std::mutex> lock(retirement_mutex_);
    --pending_retirements_;
    retirement_condition_.notify_all();
  });
}

VideoOutput::~VideoOutput() {
  destroyed_ = true;
  if (render_context_) {
    mpv_render_context_set_update_callback(render_context_, nullptr, nullptr);
  }
  thread_pool_ref_->Post([]() {}).get();
  RetireTexture(texture_id_.exchange(0));
  {
    std::unique_lock<std::mutex> lock(retirement_mutex_);
    retirement_condition_.wait(lock, [this]() { return pending_retirements_ == 0; });
  }
  thread_pool_ref_->Post([this]() {
    if (surface_manager_) surface_manager_->MakeCurrent(true);
    if (render_context_) mpv_render_context_free(render_context_);
    render_context_ = nullptr;
    if (surface_manager_) surface_manager_->MakeCurrent(false);
    surface_manager_.reset();
    pixel_buffer_.reset();
  }).get();
}
