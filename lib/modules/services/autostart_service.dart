import 'dart:io';
import 'package:flutter/foundation.dart';

/// Manages Windows startup configuration via the HKCU Run registry key.
/// Safe and does not require administrative / UAC elevation.
class AutostartService {
  static const String _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appName = 'JA_LAN_Messenger';

  /// Check if the application is currently registered to launch at Windows startup.
  static Future<bool> isAutoStartEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', [
        'query',
        _registryKey,
        '/v',
        _appName,
      ], runInShell: false);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('[AutostartService] Check error: $e');
      return false;
    }
  }

  /// Enable or disable launching at Windows startup.
  static Future<bool> setAutoStart(bool enable) async {
    if (!Platform.isWindows) return false;
    try {
      if (enable) {
        final exePath = Platform.resolvedExecutable;
        final result = await Process.run('reg', [
          'add',
          _registryKey,
          '/v',
          _appName,
          '/t',
          'REG_SZ',
          '/d',
          '"$exePath"',
          '/f',
        ], runInShell: false);
        return result.exitCode == 0;
      } else {
        final result = await Process.run('reg', [
          'delete',
          _registryKey,
          '/v',
          _appName,
          '/f',
        ], runInShell: false);
        return result.exitCode == 0;
      }
    } catch (e) {
      debugPrint('[AutostartService] Set error: $e');
      return false;
    }
  }
}
