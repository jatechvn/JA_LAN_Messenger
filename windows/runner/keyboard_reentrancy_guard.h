#ifndef RUNNER_KEYBOARD_REENTRANCY_GUARD_H_
#define RUNNER_KEYBOARD_REENTRANCY_GUARD_H_

#include <windows.h>
#include <commctrl.h>
#include <deque>

// PeekMessage inside Flutter can dispatch a synchronous SendMessage from an
// input injector. Defer only nested keyboard messages until the outer keyboard
// handler has returned, so they cannot move/clear its current event session.
class KeyboardReentrancyGuard {
 public:
  bool Install(HWND window) {
    drain_message_ = RegisterWindowMessageW(L"JA.LAN.KeyboardGuard.Drain.v1");
    return drain_message_ != 0 &&
           SetWindowSubclass(window, Procedure, kSubclassId,
                             reinterpret_cast<DWORD_PTR>(this));
  }

 private:
  struct KeyMessage { UINT message; WPARAM wparam; LPARAM lparam; };
  static constexpr UINT_PTR kSubclassId = 0x4a414b47;
  UINT drain_message_ = 0;
  bool handling_ = false;
  bool destroyed_ = false;
  std::deque<KeyMessage> pending_;

  static LRESULT CALLBACK Procedure(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id,
                                    DWORD_PTR data) {
    auto* self = reinterpret_cast<KeyboardReentrancyGuard*>(data);
    if (message == WM_NCDESTROY) {
      self->destroyed_ = true;
      self->pending_.clear();
      RemoveWindowSubclass(window, Procedure, id);
      return DefSubclassProc(window, message, wparam, lparam);
    }
    if (message == self->drain_message_) {
      if (!self->handling_) self->Drain(window);
      return 0;
    }
    if (message < WM_KEYFIRST || message > WM_KEYLAST) {
      return DefSubclassProc(window, message, wparam, lparam);
    }
    if (self->handling_) {
      self->pending_.push_back({message, wparam, lparam});
      return 0;
    }
    self->Drain(window);
    if (self->destroyed_) return 0;
    self->handling_ = true;
    const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
    self->handling_ = false;
    // Post, rather than dispatch inline: allow the original native call to
    // unwind completely. Pending messages retain their original parameters.
    if (!self->destroyed_ && !self->pending_.empty()) {
      if (!PostMessageW(window, self->drain_message_, 0, 0)) self->Drain(window);
    }
    return result;
  }

  void Drain(HWND window) {
    while (!destroyed_ && !handling_ && !pending_.empty()) {
      const auto event = pending_.front();
      pending_.pop_front();
      handling_ = true;
      // Invoke the remaining subclass chain directly, avoiding requeueing.
      DefSubclassProc(window, event.message, event.wparam, event.lparam);
      handling_ = false;
    }
  }
};
#endif
