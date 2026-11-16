# Native Windows runner (`windows/runner`)

Win32 host window, single-instance protection, DWM glass compositing, keyboard crash guard, and native OS integration channels for Windows 10 & 11.

## Files

| File | Role |
| :--- | :--- |
| [main.cpp](main.cpp) | Creates `Local\ja_lan_messenger_single_instance_mutex`, wakes/focuses existing window via `JA_LAN_MESSENGER_INSTANCE`, launches `"JA LAN Messenger"` window (`1280x720`) |
| [flutter_window.cpp](flutter_window.cpp), [flutter_window.h](flutter_window.h) | Hosts `FlutterViewController`, links `shlwapi`, registers MethodChannels `ja_lan_messenger/file_preview` (`AssocQueryStringW` / `defaultApplication`) and `ja_lan_messenger/unread_attention` (`FlashWindowEx` / `setFlash`), attaches `KeyboardReentrancyGuard`, defers initial `Show()` until first frame |
| [keyboard_reentrancy_guard.h](keyboard_reentrancy_guard.h) | Subclasses Flutter child HWND (`SetWindowSubclass`) to queue nested synchronous keyboard messages (e.g. during VNC/external IME `PeekMessage`) until outer dispatch returns |
| [win32_window.cpp](win32_window.cpp), [win32_window.h](win32_window.h) | `Win32Window` creation, DPI scaling, dark title bar (`DWMWA_USE_IMMERSIVE_DARK_MODE`), OS build detection (`IsWindows11OrGreater`), dispatches Win10 vs Win11 DWM blur |
| [theme_win10.cpp](theme_win10.cpp), [theme_win10.h](theme_win10.h) | Windows 10 `SetWindowCompositionAttribute` (Aero blur) |
| [theme_win11.cpp](theme_win11.cpp), [theme_win11.h](theme_win11.h) | Windows 11 DWM Acrylic/Mica attributes & rounded corners |
| [utils.cpp](utils.cpp), [utils.h](utils.h) | UTF-8 / UTF-16 conversion and console argument helpers |
| [Runner.rc](Runner.rc), [resource.h](resource.h), [runner.exe.manifest](runner.exe.manifest), [CMakeLists.txt](CMakeLists.txt) | Embeds `../../assets/app_icon.ico`, PE branding (`JA LAN Messenger`, product version synced with `pubspec.yaml`), DPI manifest & CMake target (`comctl32`, `shlwapi`, `dwmapi`) |

## Verification

- Guard unit test: [test/keyboard_reentrancy_guard_test.cpp](../../test/keyboard_reentrancy_guard_test.cpp)
- Branding/RC contract test: [test/windows_application_name_test.dart](../../test/windows_application_name_test.dart)
- Syntax check with MSVC before committing native edits:
  `cl /Zs /std:c++17 /W4 /WX /DUNICODE /D_UNICODE windows\runner\win32_window.cpp windows\runner\main.cpp`
