import 'dart:io';
import 'package:flutter/foundation.dart';
import 'constants.dart';

class BuildInfo {
  static bool isCliDebug = false;
  static final String debugTimestamp = _generateBuildTimestamp();

  static String _generateBuildTimestamp() {
    try {
      final exeFile = File(Platform.resolvedExecutable);
      final appSoFile = File(
        '${exeFile.parent.path}${Platform.pathSeparator}data${Platform.pathSeparator}app.so',
      );
      final targetFile = appSoFile.existsSync() ? appSoFile : exeFile;

      if (targetFile.existsSync()) {
        final modified = targetFile.lastModifiedSync();
        return '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} '
            '${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}:${modified.second.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  static bool get isDebug => kDebugMode || isCliDebug;
  static const String version = appVersion;
}
