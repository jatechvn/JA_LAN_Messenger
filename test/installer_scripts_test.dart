import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows installer and uninstaller execute in isolated sandbox',
    () async {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        '${Directory.current.path}/test/installer_smoke.ps1',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
