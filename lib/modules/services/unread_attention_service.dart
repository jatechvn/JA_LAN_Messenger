import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import 'tray_badge_service.dart';

/// Serializes native writes and coalesces changes while an icon is loading.
class UnreadAttentionService {
  UnreadAttentionService({
    Future<void> Function(String)? setIcon,
    Future<String?> Function(int)? badgePath,
    Future<void> Function(bool)? flashTaskbar,
  }) : _setIcon = setIcon ?? ((path) => trayManager.setIcon(path)),
       _badgePath = badgePath ?? TrayBadgeService.getBadgeIconPath,
       _flashTaskbar = flashTaskbar ?? _nativeFlash;

  static const _channel = MethodChannel('ja_lan_messenger/unread_attention');
  static const interval = Duration(milliseconds: 750);
  static const normalIcon = 'assets/app_icon.ico';
  final Future<void> Function(String) _setIcon;
  final Future<String?> Function(int) _badgePath;
  final Future<void> Function(bool) _flashTaskbar;
  Timer? _timer;
  int _unread = -1;
  bool _bright = false;
  bool _dirty = false;
  bool _busy = false;
  bool _disposed = false;
  bool? _taskbarActive;

  static Future<void> _nativeFlash(bool active) async {
    if (Platform.isWindows) {
      await _channel.invokeMethod<void>('setFlash', active);
    }
  }

  void update(int unread) {
    if (_disposed || unread == _unread) return;
    _unread = unread;
    _bright = unread > 0;
    if (unread > 0) {
      _timer ??= Timer.periodic(interval, (_) {
        _bright = !_bright;
        _refresh();
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
    _refresh();
  }

  void _refresh() {
    _dirty = true;
    if (!_busy) unawaited(_drain());
  }

  Future<void> _drain() async {
    _busy = true;
    try {
      while (_dirty) {
        _dirty = false;
        final count = _unread;
        final bright = _bright && count > 0;
        var path = normalIcon;
        try {
          if (bright) path = await _badgePath(count) ?? normalIcon;
        } catch (error) {
          debugPrint('[UnreadAttention] Badge: $error');
        }
        if (_dirty) continue; // A newer count/phase supersedes this render.
        try {
          await _setIcon(path);
        } catch (error) {
          debugPrint('[UnreadAttention] Tray: $error');
        }
        if (_dirty) continue;
        try {
          // Windows owns its flash timer. Tray phases must not stop/restart it.
          final active = count > 0;
          if (_taskbarActive != active) {
            await _flashTaskbar(active);
            _taskbarActive = active;
          }
        } catch (error) {
          debugPrint('[UnreadAttention] Taskbar: $error');
        }
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _unread = 0;
    _bright = false;
    _refresh();
  }
}
