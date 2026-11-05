    valid_ = false;
    compositor_ = nullptr;
    graphics_context_ = nullptr;
    if (dispatcher_queue_controller_) {
      winrt::Windows::Foundation::IAsyncAction shutdown{nullptr};
      if (SUCCEEDED(dispatcher_queue_controller_->ShutdownQueueAsync(
              reinterpret_cast<ABI::Windows::Foundation::IAsyncAction**>(
                  winrt::put_abi(shutdown))))) {
        bool quit_requested = false;
        int quit_code = 0;
        while (shutdown.Status() ==
               winrt::Windows::Foundation::AsyncStatus::Started) {
          MSG message{};
          if (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) {
              quit_requested = true;
              quit_code = static_cast<int>(message.wParam);
            } else {
              TranslateMessage(&message);
              DispatchMessage(&message);
            }
          } else {
            MsgWaitForMultipleObjectsEx(0, nullptr, 10, QS_ALLINPUT,
                                       MWMO_INPUTAVAILABLE);
          }
        }
        if (quit_requested) PostQuitMessage(quit_code);
      }
      dispatcher_queue_controller_ = nullptr;
    }
    rohelper_ = nullptr;
