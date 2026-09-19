import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/ota_update_service.dart';

// Opt-in only: prepares an installer for a disposable app, never the running app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rootPath = Platform.environment['JA_OTA_SMOKE_ROOT'];
  final serverPath = Platform.environment['JA_OTA_SMOKE_SERVER'];
  test(
    'Stage real SMB package and prepare isolated installer',
    () async {
      final root = Directory(rootPath!);
      expect(Platform.environment['APPDATA'], startsWith(root.path));
      expect(Platform.environment['LOCALAPPDATA'], startsWith(root.path));
      final service = OtaUpdateService();
      AppPreferences().setCustomFileForTesting(File('${root.path}/prefs.json'));
      addTearDown(() => AppPreferences().setCustomFileForTesting(null));
      final result = await service.checkForUpdates(
        overrideServerPath: serverPath!,
        overrideCurrentVersion: '0.0.0',
      );
      expect(result.isConnectionSuccess, true, reason: result.errorMessage);
      expect(result.hasUpdate, true);
      final package = result.packageInfo!;
      final same = await service.checkForUpdates(
        overrideServerPath: serverPath,
        overrideCurrentVersion: package.version.toString(),
      );
      expect(same.hasUpdate, false);
      final source = await service.validatePackageForTesting(package);
      final target = await Directory('${root.path}/portable').create();
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        final relative = entity.path.substring(source.path.length);
        if (entity is Directory) {
          await Directory('${target.path}$relative').create(recursive: true);
        } else if (entity is File) {
          final dest = File('${target.path}$relative');
          await dest.parent.create(recursive: true);
          await entity.copy(dest.path);
        }
      }
      await File(
        '${target.path}/README.md',
      ).writeAsString('OTA old file sentinel');
      await File(
        '${target.path}/user_preferences.json',
      ).writeAsString('{"smoke":true}');
      final exited = await Process.start('cmd.exe', ['/c', 'exit', '0']);
      await exited.exitCode;
      final script = OtaUpdateService.generateApplyUpdateScript(
        oldPid: exited.pid,
        sourceDir: source.path,
        targetDir: target.path,
        exeName: 'ja_lan_messenger.exe',
      );
      await File('${root.path}/apply_update.bat').writeAsString(script);
      await File('${root.path}/prepared.json').writeAsString(
        jsonEncode({
          'source': source.path,
          'target': target.path,
          'package': package.fileName,
          'bytes': package.fileSize,
        }),
      );
    },
    skip: !Platform.isWindows || rootPath == null || serverPath == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
