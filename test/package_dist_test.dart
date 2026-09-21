import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Packaging preserves output and rejects stale binaries',
    () async {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          '${Directory.current.path}/test/package_dist_smoke.ps1',
        ],
        environment: {
          'PSModulePath':
              '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\Modules',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
