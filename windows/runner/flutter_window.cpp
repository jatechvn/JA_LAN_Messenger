#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  attention_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "ja_lan_messenger/unread_attention",
          &flutter::StandardMethodCodec::GetInstance());
  attention_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setFlash") {
          result->NotImplemented();
          return;
        }
        const auto* active = call.arguments()
            ? std::get_if<bool>(call.arguments()) : nullptr;
        if (!active) {
          result->Error("invalid_argument", "Expected a boolean");
          return;
        }
        // Windows owns the repeating cadence; Dart sends only start/stop.
        // Do not use TIMERNOFG: focusing alone does not mean messages were read.
        FLASHWINFO info{};
        info.cbSize = sizeof(info);
        info.hwnd = GetHandle();
        info.dwFlags = *active ? (FLASHW_TRAY | FLASHW_TIMER) : FLASHW_STOP;
        info.uCount = 0;  // FLASHW_TIMER repeats until explicitly stopped.
        info.dwTimeout = 750;
        FlashWindowEx(&info);
        result->Success();
      });
  if (!keyboard_guard_.Install(flutter_controller_->view()->GetNativeWindow())) {
    return false;
  }
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (attention_channel_) {
    attention_channel_->SetMethodCallHandler(nullptr);
    attention_channel_.reset();
  }
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    ::RemovePropW(hwnd, L"JA_LAN_MESSENGER_INSTANCE");
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
