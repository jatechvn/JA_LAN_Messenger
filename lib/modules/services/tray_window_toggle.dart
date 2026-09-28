import 'package:window_manager/window_manager.dart';

/// Tray clicks can steal focus; visibility, not focus, determines the toggle.
class TrayWindowToggle {
  bool _busy = false;

  Future<void> toggle() async {
    if (_busy) return;
    _busy = true;
    try {
      final visible = await windowManager.isVisible();
      final minimized = await windowManager.isMinimized();
      if (visible && !minimized) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    } finally {
      _busy = false;
    }
  }
}
