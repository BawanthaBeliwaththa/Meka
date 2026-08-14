#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame;
  GetClientRect(GetHandle(), &frame);

  controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);

  if (!controller_->engine() || !controller_->view()) {
    return false;
  }
  RegisterPlugins(controller_->engine());

  return true;
}

void FlutterWindow::OnDestroy() {
  if (controller_) {
    controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (controller_) {
    std::optional<LRESULT> result =
        controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
