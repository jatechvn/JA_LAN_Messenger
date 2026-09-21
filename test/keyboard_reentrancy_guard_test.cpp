#include "../windows/runner/keyboard_reentrancy_guard.h"
#include <vector>
#include <iostream>
#include <thread>
#include <atomic>

static bool active = false;
static bool nested = false;
static bool cross_thread = false;
static std::vector<UINT> received;
static LRESULT CALLBACK WindowProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg >= WM_KEYFIRST && msg <= WM_KEYLAST) {
    if (active) nested = true;
    received.push_back(msg);
    if (msg == WM_KEYDOWN) {
      active = true;
      if (cross_thread) {
        std::atomic<bool> done{false};
        std::thread injector([&] {
          SendMessageW(hwnd, WM_CHAR, L'a', lp);
          SendMessageW(hwnd, WM_KEYUP, wp, lp);
          done = true;
        });
        MSG pending{};
        while (!done) {
          // Match Flutter peeking the keyboard queue while a remote input
          // thread synchronously sends a character to the same window.
          PeekMessageW(&pending, hwnd, WM_KEYFIRST, WM_KEYLAST, PM_NOREMOVE);
          Sleep(1);
        }
        injector.join();
      } else {
        SendMessageW(hwnd, WM_CHAR, L'a', lp);
        SendMessageW(hwnd, WM_KEYUP, wp, lp);
      }
      active = false;
    }
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}
int main() {
  WNDCLASSW cls{};
  cls.lpfnWndProc = WindowProc;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"JA.KeyboardGuard.Test";
  if (!RegisterClassW(&cls)) return 1;
  HWND window = CreateWindowW(cls.lpszClassName, L"", 0, 0, 0, 0, 0,
                              HWND_MESSAGE, nullptr, cls.hInstance, nullptr);
  if (!window) return 2;
  SendMessageW(window, WM_KEYDOWN, L'A', 1);
  if (!nested) return 3;  // Fixture must reproduce nested native input first.
  nested = false;
  received.clear();
  KeyboardReentrancyGuard guard;
  if (!guard.Install(window)) return 4;
  SendMessageW(window, WM_KEYDOWN, L'A', 1);
  // A later key must not overtake the already deferred messages.
  SendMessageW(window, WM_SYSKEYUP, VK_MENU, 1);
  MSG message{};
  while (PeekMessageW(&message, window, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
  const std::vector<UINT> expected{WM_KEYDOWN, WM_CHAR, WM_KEYUP, WM_SYSKEYUP};
  if (nested || received != expected) return 5;
  received.clear();
  cross_thread = true;
  SendMessageW(window, WM_KEYDOWN, L'A', 1);
  while (PeekMessageW(&message, window, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
  if (nested || received != std::vector<UINT>{WM_KEYDOWN, WM_CHAR, WM_KEYUP}) return 6;
  cross_thread = false;
  SendMessageW(window, WM_KEYDOWN, L'A', 1);
  DestroyWindow(window); // Teardown with a pending drain must be safe.
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
  std::cout << "PASS: baseline reentrancy, guarded input order, pending teardown\n";
  return 0;
}
