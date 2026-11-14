import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/ota_update_service.dart';

void main() {
  group('Installer & OTA Directory Unlock Verification', () {
    test(
      'install.bat releases installer folder CWD before setlocal and hands off prompt to %TEMP%',
      () {
        final installBat = File('install.bat').readAsStringSync();
        final cdTempIdx = installBat.indexOf('cd /d "%TEMP%"');
        final setlocalIdx = installBat.indexOf('setlocal EnableExtensions');
        expect(cdTempIdx, isNonNegative);
        expect(setlocalIdx, greaterThan(cdTempIdx));
        expect(installBat, contains('cd /d "%TARGET_DIR%"'));
        expect(
          installBat,
          contains(
            'start "" /D "%TARGET_DIR%" "%TARGET_DIR%\\ja_lan_messenger.exe"',
          ),
        );
        expect(installBat, contains('ja_lan_post_install_'));
      },
    );

    test(
      'OtaUpdateService.generateApplyUpdateScript anchors CWD and passes /D "%DST_DIR%"',
      () {
        final script = OtaUpdateService.generateApplyUpdateScript(
          oldPid: 4321,
          sourceDir: r'C:\Temp\JA_Update\extracted',
          targetDir: r'C:\Users\Test\AppData\Local\Programs\JA_LAN_Messenger',
          exeName: 'ja_lan_messenger.exe',
        );
        expect(script, contains('cd /d "%DST_DIR%"'));
        expect(
          script,
          contains(
            'start "" /D "%DST_DIR%" "%DST_DIR%\\%EXE_NAME%" "--ota-session=%~dp0."',
          ),
        );
      },
    );

    test(
      'Real install.bat unlocks installerDir during FINISH_BAT prompt handoff and while launched app runs',
      () async {
        if (!Platform.isWindows) return;

        final root = await Directory.systemTemp.createTemp('ja_inst_unlock_');
        final regKey =
            'HKCU\\Software\\JA_LAN_Messenger_Test_${DateTime.now().millisecondsSinceEpoch}';
        addTearDown(() async {
          await Process.run('reg', ['delete', regKey, '/f']);
          for (var i = 0; i < 10; i++) {
            try {
              if (root.existsSync()) {
                root.deleteSync(recursive: true);
              }
              break;
            } catch (_) {
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
          }
        });

        final installerDir = Directory('${root.path}\\installer_pkg')
          ..createSync(recursive: true);
        final targetDir = Directory('${root.path}\\installed_app');
        final desktopDir = Directory('${root.path}\\desktop')
          ..createSync(recursive: true);
        final startMenuDir = Directory('${root.path}\\start_menu')
          ..createSync(recursive: true);

        // Copy real installer scripts into installerDir
        File('install.bat').copySync('${installerDir.path}\\install.bat');
        File('uninstall.ps1').copySync('${installerDir.path}\\uninstall.ps1');
        if (File('uninstall.bat').existsSync()) {
          File('uninstall.bat').copySync('${installerDir.path}\\uninstall.bat');
        }

        // Create required payload files in installerDir
        File(
          '${installerDir.path}\\flutter_windows.dll',
        ).writeAsStringSync('stub_dll');
        Directory('${installerDir.path}\\data').createSync(recursive: true);
        File(
          '${installerDir.path}\\data\\icudtl.dat',
        ).writeAsStringSync('stub_icu');
        File(
          '${installerDir.path}\\data\\app.so',
        ).writeAsStringSync('stub_aot');

        // Compile a tiny real Windows executable for ja_lan_messenger.exe
        // that records its CurrentDirectory and stays alive for 1.2s
        final cscPath =
            r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe';
        expect(File(cscPath).existsSync(), isTrue);
        final csSource = File('${root.path}\\stub_app.cs');
        csSource.writeAsStringSync('''
using System;
using System.IO;
using System.Threading;
class StubApp {
  static void Main(string[] args) {
    string marker = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launched_cwd.txt");
    File.WriteAllText(marker, Environment.CurrentDirectory);
    Thread.Sleep(1200);
  }
}
''');
        final compileRes = await Process.run(cscPath, [
          '/nologo',
          '/target:winexe',
          '/out:${installerDir.path}\\ja_lan_messenger.exe',
          csSource.path,
        ]);
        expect(
          compileRes.exitCode,
          0,
          reason: 'csc failed: ${compileRes.stdout} ${compileRes.stderr}',
        );

        // Start the REAL install.bat with workingDirectory = installerDir.path
        final proc = await Process.start(
          'cmd.exe',
          ['/c', '${installerDir.path}\\install.bat'],
          workingDirectory: installerDir.path,
          environment: {
            ...Platform.environment,
            'JA_INSTALL_TARGET_DIR': targetDir.path,
            'JA_INSTALL_DESKTOP_DIR': desktopDir.path,
            'JA_INSTALL_START_MENU_DIR': startMenuDir.path,
            'JA_INSTALL_REG_KEY': regKey,
          },
        );

        final outputBuffer = StringBuffer();
        final reachedDoneBanner = Completer<void>();
        proc.stdout.transform(utf8.decoder).listen((chunk) {
          outputBuffer.write(chunk);
          if (!reachedDoneBanner.isCompleted &&
              outputBuffer.toString().contains(
                '[DONE] JA LAN MESSENGER INSTALLED SUCCESSFULLY!',
              )) {
            reachedDoneBanner.complete();
          }
        });
        proc.stderr.transform(utf8.decoder).listen(outputBuffer.write);

        await reachedDoneBanner.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () =>
              fail('install.bat did not reach [DONE]: $outputBuffer'),
        );

        // Wait briefly for handoff to %FINISH_BAT% and `set /p RUN_APP=...` prompt
        await Future<void>.delayed(const Duration(milliseconds: 400));

        // 1. Delete installerDir WHILE the prompt in %FINISH_BAT% is still open!
        installerDir.deleteSync(recursive: true);
        expect(
          installerDir.existsSync(),
          isFalse,
          reason: 'installerDir must be deletable while prompt is open',
        );

        // 2. Answer "Y" to the prompt to launch %TARGET_DIR%\ja_lan_messenger.exe
        proc.stdin.writeln('Y');
        await proc.stdin.close();

        final exitCode = await proc.exitCode.timeout(
          const Duration(seconds: 10),
        );
        expect(exitCode, 0, reason: 'install.bat output: $outputBuffer');

        // 3. Wait for launched ja_lan_messenger.exe to write its CWD marker file
        final markerFile = File('${targetDir.path}\\launched_cwd.txt');
        for (var i = 0; i < 20 && !markerFile.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          markerFile.existsSync(),
          isTrue,
          reason: 'Launched app did not create launched_cwd.txt in targetDir',
        );
        expect(
          markerFile.readAsStringSync().trim().toLowerCase(),
          equals(targetDir.path.toLowerCase()),
        );
        expect(installerDir.existsSync(), isFalse);
      },
    );
  });
}
