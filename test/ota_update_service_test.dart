import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/ota_update_service.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/settings_dialog.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_update_dialog.dart';
import 'package:ja_lan_messenger/modules/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File prefFile;
  late File configFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ota_test_');
    prefFile = File('${tempDir.path}/user_preferences.json');
    configFile = File('${tempDir.path}/update_config.json');

    AppPreferences().setCustomFileForTesting(prefFile);
    LanguageProvider.disableDiskPersistenceForTesting = true;
    OtaUpdateService().setCustomConfigFileForTesting(configFile);
    OtaUpdateService().setCustomServerDirForTesting(null);
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    LanguageProvider.disableDiskPersistenceForTesting = false;
    OtaUpdateService().setCustomConfigFileForTesting(null);
    OtaUpdateService().setCustomServerDirForTesting(null);

    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('SemanticVersion Unit Tests', () {
    test('Release follows rc and malformed versions are rejected', () {
      expect(
        SemanticVersion.tryParse('1.2.0-rc.2')! <
            SemanticVersion.tryParse('1.2.0-rc.10')!,
        true,
      );
      expect(
        SemanticVersion.tryParse('1.2.0-rc.10')! <
            SemanticVersion.tryParse('1.2.0')!,
        true,
      );
      expect(SemanticVersion.tryParse('1.2.3.4'), isNull);
      expect(
        SemanticVersion.tryParse('1.2.0')!.hashCode,
        SemanticVersion.tryParse('1.2.0+0')!.hashCode,
      );
      expect(OtaUpdateService.isValidPackageName('../other_v9.0.0.zip'), false);
      expect(OtaUpdateService.isValidPackageName('OtherApp_v9.0.0.zip'), false);
    });
    test(
      'Real ZIP staging rejects missing runtime without starting installer',
      () async {
        if (!Platform.isWindows) return;
        final source = Directory('${tempDir.path}/payload')..createSync();
        File(
          '${source.path}/ja_lan_messenger.exe',
        ).writeAsStringSync('fixture');
        final zip = File('${tempDir.path}/test.zip');
        Future<void> pack() async {
          final result = await Process.run('tar', [
            '-a',
            '-cf',
            zip.path,
            '-C',
            source.path,
            '.',
          ]);
          expect(result.exitCode, 0);
        }

        UpdatePackageInfo package() => UpdatePackageInfo(
          version: SemanticVersion.tryParse('2.0.0')!,
          fileName: 'test.zip',
          fullPath: zip.path,
          fileSize: zip.lengthSync(),
        );
        await pack();
        await expectLater(
          OtaUpdateService().validatePackageForTesting(package()),
          throwsStateError,
        );
        File('${source.path}/flutter_windows.dll').writeAsStringSync('fixture');
        Directory('${source.path}/data').createSync();
        File('${source.path}/data/icudtl.dat').writeAsStringSync('fixture');
        await pack();
        await OtaUpdateService().validatePackageForTesting(package());
      },
    );
    test('Correctly parses SemVer formats with and without prefix', () {
      final v1 = SemanticVersion.tryParse('1.0.0');
      expect(v1, isNotNull);
      expect(v1!.major, equals(1));
      expect(v1.minor, equals(0));
      expect(v1.patch, equals(0));
      expect(v1.build, isNull);

      final v2 = SemanticVersion.tryParse('v2.4.1+15');
      expect(v2, isNotNull);
      expect(v2!.major, equals(2));
      expect(v2.minor, equals(4));
      expect(v2.patch, equals(1));
      expect(v2.build, equals(15));

      final v3 = SemanticVersion.tryParse('1.1');
      expect(v3, isNotNull);
      expect(v3!.major, equals(1));
      expect(v3.minor, equals(1));
      expect(v3.patch, equals(0));

      final vInvalid = SemanticVersion.tryParse('invalid_version_string');
      expect(vInvalid, isNull);

      final vNull = SemanticVersion.tryParse(null);
      expect(vNull, isNull);
    });

    test('SemanticVersion comparison operators work correctly', () {
      final v100 = SemanticVersion.tryParse('1.0.0')!;
      final v101 = SemanticVersion.tryParse('1.0.1')!;
      final v110 = SemanticVersion.tryParse('1.1.0')!;
      final v200 = SemanticVersion.tryParse('2.0.0')!;
      final v100b1 = SemanticVersion.tryParse('1.0.0+1')!;
      final v100b2 = SemanticVersion.tryParse('1.0.0+2')!;

      expect(v100 < v101, isTrue);
      expect(v101 < v110, isTrue);
      expect(v110 < v200, isTrue);
      expect(v200 > v110, isTrue);
      expect(v100b1 < v100b2, isTrue);
      expect(v100 == SemanticVersion.tryParse('1.0.0')!, isTrue);
      expect(v110 >= v100, isTrue);
      expect(v100 <= v110, isTrue);
      expect(v100 > v110, isFalse);
    });

    test('SemanticVersion string representation is consistent', () {
      final v1 = SemanticVersion.tryParse('1.2.3')!;
      expect(v1.toString(), equals('1.2.3'));

      final v2 = SemanticVersion.tryParse('v1.2.3+4')!;
      expect(v2.toString(), equals('1.2.3+4'));
    });
  });

  group('UpdatePackageInfo & OtaUpdateConfig Tests', () {
    test('formattedSize converts bytes to human-readable units', () {
      final pkg0 = UpdatePackageInfo(
        version: SemanticVersion.tryParse('1.0.0')!,
        fileName: 'test.zip',
        fullPath: '/path/test.zip',
        fileSize: 0,
      );
      expect(pkg0.formattedSize, equals('0 B'));

      final pkgKb = UpdatePackageInfo(
        version: SemanticVersion.tryParse('1.0.0')!,
        fileName: 'test.zip',
        fullPath: '/path/test.zip',
        fileSize: 1024,
      );
      expect(pkgKb.formattedSize, equals('1.00 KB'));

      final pkgMb = UpdatePackageInfo(
        version: SemanticVersion.tryParse('1.0.0')!,
        fileName: 'test.zip',
        fullPath: '/path/test.zip',
        fileSize: 14 * 1024 * 1024 + 512 * 1024,
      );
      expect(pkgMb.formattedSize, contains('MB'));

      final pkgGb = UpdatePackageInfo(
        version: SemanticVersion.tryParse('1.0.0')!,
        fileName: 'test.zip',
        fullPath: '/path/test.zip',
        fileSize: 2 * 1024 * 1024 * 1024,
      );
      expect(pkgGb.formattedSize, contains('GB'));
    });

    test('OtaUpdateConfig serialization and deserialization', () {
      final config = OtaUpdateConfig(
        serverPath: r'\\server\share\updates',
        username: 'admin',
        password: 'secretPassword',
        checkInterval: 'weekly',
        autoDownload: true,
      );

      final json = config.toJson();
      expect(json['serverPath'], equals(r'\\server\share\updates'));
      expect(json['username'], equals('admin'));
      expect(json['password'], equals('secretPassword'));
      expect(json['checkInterval'], equals('weekly'));
      expect(json['autoDownload'], isTrue);

      final parsed = OtaUpdateConfig.fromJson(json);
      expect(parsed.serverPath, equals(config.serverPath));
      expect(parsed.username, equals(config.username));
      expect(parsed.password, equals(config.password));
      expect(parsed.checkInterval, equals(config.checkInterval));
      expect(parsed.autoDownload, equals(config.autoDownload));
    });

    test(
      'OtaUpdateConfig defaults use user-requested server and credentials',
      () {
        final defaults = OtaUpdateConfig.defaults();
        expect(defaults.serverPath, contains(r'10.81.141.226'));
        expect(defaults.serverPath, contains('JA_Update'));
        expect(defaults.username, equals('user'));
        expect(defaults.password, equals('user'));
        expect(defaults.checkInterval, equals('daily'));
      },
    );
  });

  group('OtaUpdateService Logic Tests', () {
    test('extractSmbShareRoot properly parses UNC root path', () {
      expect(
        OtaUpdateService.extractSmbShareRoot(
          r'\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger',
        ),
        equals(r'\\10.81.141.226\temp'),
      );

      expect(
        OtaUpdateService.extractSmbShareRoot(r'\\192.168.1.100\SharedFolder'),
        equals(r'\\192.168.1.100\SharedFolder'),
      );

      // Forward slash normalized
      expect(
        OtaUpdateService.extractSmbShareRoot('//10.81.141.226/temp/subfolder'),
        equals(r'\\10.81.141.226\temp'),
      );

      // Non-UNC paths return null
      expect(OtaUpdateService.extractSmbShareRoot(r'C:\LocalFolder'), isNull);
    });

    test(
      'shouldCheckForUpdates respects configured intervals and elapsed time',
      () {
        final service = OtaUpdateService();
        final now = DateTime(2026, 9, 19, 12, 0, 0);

        // Interval off always returns false
        expect(
          service.shouldCheckForUpdates(
            interval: 'off',
            lastCheckTime: null,
            now: now,
          ),
          isFalse,
        );
        expect(
          service.shouldCheckForUpdates(
            interval: 'off',
            lastCheckTime: now.subtract(const Duration(days: 365)),
            now: now,
          ),
          isFalse,
        );

        // If never checked before, returns true
        expect(
          service.shouldCheckForUpdates(
            interval: 'daily',
            lastCheckTime: null,
            now: now,
          ),
          isTrue,
        );

        // Daily: 23 hours ago -> false, 25 hours ago -> true
        expect(
          service.shouldCheckForUpdates(
            interval: 'daily',
            lastCheckTime: now.subtract(const Duration(hours: 23)),
            now: now,
          ),
          isFalse,
        );
        expect(
          service.shouldCheckForUpdates(
            interval: 'daily',
            lastCheckTime: now.subtract(const Duration(hours: 25)),
            now: now,
          ),
          isTrue,
        );

        // Weekly: 6 days ago -> false, 8 days ago -> true
        expect(
          service.shouldCheckForUpdates(
            interval: 'weekly',
            lastCheckTime: now.subtract(const Duration(days: 6)),
            now: now,
          ),
          isFalse,
        );
        expect(
          service.shouldCheckForUpdates(
            interval: 'weekly',
            lastCheckTime: now.subtract(const Duration(days: 8)),
            now: now,
          ),
          isTrue,
        );

        // Monthly: 25 days ago -> false, 31 days ago -> true
        expect(
          service.shouldCheckForUpdates(
            interval: 'monthly',
            lastCheckTime: now.subtract(const Duration(days: 25)),
            now: now,
          ),
          isFalse,
        );
        expect(
          service.shouldCheckForUpdates(
            interval: 'monthly',
            lastCheckTime: now.subtract(const Duration(days: 31)),
            now: now,
          ),
          isTrue,
        );
      },
    );

    test('External configuration saving and loading', () async {
      final service = OtaUpdateService();
      final config = OtaUpdateConfig(
        serverPath: r'\\custom_server\share',
        username: 'custom_user',
        password: 'custom_pass',
        checkInterval: 'weekly',
        autoDownload: false,
      );

      await service.saveExternalConfigFile(config);
      expect(configFile.existsSync(), isTrue);

      final loaded = await service.loadExternalConfigFile();
      expect(loaded, isNotNull);
      expect(loaded!.serverPath, equals(config.serverPath));
      expect(loaded.username, equals(config.username));
      expect(loaded.password, equals(config.password));
      expect(loaded.checkInterval, equals('weekly'));
    });

    test('syncExternalConfigToPreferences updates AppPreferences', () async {
      final service = OtaUpdateService();
      final prefs = AppPreferences();
      await prefs.load();

      final customConfig = OtaUpdateConfig(
        serverPath: r'\\synced_server\update_folder',
        username: 'sync_user',
        password: 'sync_password',
        checkInterval: 'monthly',
      );
      await service.saveExternalConfigFile(customConfig);

      await service.syncExternalConfigToPreferences();

      expect(prefs.otaServerPath, equals(r'\\synced_server\update_folder'));
      expect(prefs.otaUsername, equals('sync_user'));
      expect(prefs.otaPassword, equals('sync_password'));
      expect(prefs.otaCheckInterval, equals('monthly'));
    });

    test('generateApplyUpdateScript contains critical batch commands', () {
      final script = OtaUpdateService.generateApplyUpdateScript(
        oldPid: 1234,
        sourceDir: r'C:\Temp\Update\extracted',
        targetDir: r'C:\Apps\JA_LAN_Messenger',
        exeName: 'ja_lan_messenger.exe',
      );

      expect(script, contains('OLD_PID=1234'));
      expect(script, contains('robocopy'));
      expect(script, contains('ja_lan_messenger.exe'));
      expect(script, contains('tasklist /fi "PID eq %OLD_PID%"'));
      expect(script, contains('start ""'));
    });

    test('checkForUpdates discovers newer version from version.json', () async {
      final service = OtaUpdateService();
      final serverDir = Directory('${tempDir.path}/mock_server');
      await serverDir.create(recursive: true);
      service.setCustomServerDirForTesting(serverDir);

      // Create dummy zip file
      final zipFile = File('${serverDir.path}/JA_LAN_Messenger_v1.2.0.zip');
      await zipFile.writeAsBytes([1, 2, 3, 4]);

      // Create version.json pointing to higher version
      final versionJson = File('${serverDir.path}/version.json');
      await versionJson.writeAsString(
        jsonEncode({
          'version': '1.2.0',
          'fileName': 'JA_LAN_Messenger_v1.2.0.zip',
          'releaseNotes': 'Tính năng cập nhật OTA tự động',
          'releaseDate': '2026-09-19',
        }),
      );

      final result = await service.checkForUpdates(
        overrideCurrentVersion: '1.0.0',
      );

      expect(result.hasUpdate, isTrue);
      expect(result.packageInfo, isNotNull);
      expect(result.packageInfo!.version.toString(), equals('1.2.0'));
      expect(result.packageInfo!.releaseNotes, contains('cập nhật OTA'));

      // If current version is already 1.2.0 or higher
      final sameResult = await service.checkForUpdates(
        overrideCurrentVersion: '1.2.0',
      );
      expect(sameResult.hasUpdate, isFalse);
    });

    test(
      'checkForUpdates discovers newer version by scanning .zip filename',
      () async {
        final service = OtaUpdateService();
        final serverDir = Directory('${tempDir.path}/mock_server_zip');
        await serverDir.create(recursive: true);
        service.setCustomServerDirForTesting(serverDir);

        // Create multiple dummy zips
        final zipOld = File(
          '${serverDir.path}/JA_LAN_Messenger_v1.0.5_Windows_x64.zip',
        );
        await zipOld.writeAsBytes([1, 2, 3]);

        final zipNew = File(
          '${serverDir.path}/JA_LAN_Messenger_v1.3.0_Windows_x64.zip',
        );
        await zipNew.writeAsBytes([1, 2, 3, 4, 5]);

        final result = await service.checkForUpdates(
          overrideCurrentVersion: '1.1.0',
        );

        expect(result.hasUpdate, isTrue);
        expect(result.packageInfo, isNotNull);
        expect(result.packageInfo!.version.toString(), equals('1.3.0'));
        expect(
          result.packageInfo!.fileName,
          equals('JA_LAN_Messenger_v1.3.0_Windows_x64.zip'),
        );
      },
    );
  });

  group('MessengerCoordinator OTA Integration Tests', () {
    test('availableUpdate state management and dismiss', () {
      final coordinator = MessengerCoordinator();
      expect(coordinator.availableUpdate, isNull);

      final updatePkg = UpdatePackageInfo(
        version: SemanticVersion.tryParse('1.5.0')!,
        fileName: 'JA_LAN_Messenger_v1.5.0.zip',
        fullPath: '/tmp/test.zip',
        fileSize: 1024 * 1024,
      );

      coordinator.setAvailableUpdateForTesting(updatePkg);
      expect(coordinator.availableUpdate, isNotNull);
      expect(coordinator.availableUpdate!.version.toString(), equals('1.5.0'));

      coordinator.dismissAvailableUpdate();
      expect(coordinator.availableUpdate, isNull);
    });

    test(
      'checkOtaUpdates sets availableUpdate and triggers toast when update exists',
      () async {
        final service = OtaUpdateService();
        final serverDir = Directory('${tempDir.path}/mock_server_coordinator');
        await serverDir.create(recursive: true);
        service.setCustomServerDirForTesting(serverDir);

        final zipNew = File('${serverDir.path}/JA_LAN_Messenger_v2.0.0.zip');
        await zipNew.writeAsBytes([1, 2]);

        final coordinator = MessengerCoordinator();
        final prefs = AppPreferences();
        await prefs.load();
        await prefs.setOtaSettings(serverPath: serverDir.path);

        final result = await coordinator.checkOtaUpdates(isManual: true);
        expect(result.hasUpdate, isTrue);
        expect(coordinator.availableUpdate, isNotNull);
        expect(
          coordinator.availableUpdate!.version.toString(),
          equals('2.0.0'),
        );
        expect(coordinator.currentToast?.key, equals('updateAvailable'));
      },
    );
  });

  group('Localization OTA Keys Verification', () {
    test('All OTA localization keys exist across vi, en, zh', () {
      final lang = LanguageProvider();
      const keys = [
        'tabUpdate',
        'otaUpdateTitle',
        'otaUpdateDesc',
        'otaCheckInterval',
        'intervalDaily',
        'intervalWeekly',
        'intervalMonthly',
        'intervalOff',
        'otaServerPath',
        'otaServerPathHint',
        'otaUsername',
        'otaPassword',
        'checkUpdatesNow',
        'checkingUpdates',
        'noUpdatesAvailable',
        'updateAvailable',
        'updateNow',
        'updateLater',
        'downloadingUpdate',
        'extractingUpdate',
        'readyToRestart',
        'testServerConnection',
        'serverConnectionSuccess',
        'serverConnectionFailed',
        'openConfigFolder',
        'currentVersion',
        'latestVersion',
        'lastChecked',
        'neverChecked',
        'releaseNotes',
        'updateError',
      ];

      for (final locale in AppLanguage.values) {
        lang.setLanguage(locale);
        for (final key in keys) {
          final translated = lang.tr(key);
          expect(
            translated,
            isNotEmpty,
            reason: 'Key "$key" should have translation in ${locale.name}',
          );
          expect(
            translated,
            isNot(equals(key)),
            reason: 'Key "$key" was not found in dictionary for ${locale.name}',
          );
        }
      }
    });
  });

  group('OTA Widgets UI Tests', () {
    testWidgets('SettingsDialog renders 4 tabs including OTA tab', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsDialog())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Tab bar has 4 tabs
      expect(find.byType(Tab), findsNWidgets(4));
      expect(find.text(lang.tr('tabUpdate')), findsOneWidget);

      // Tap OTA Update tab (Index 1)
      await tester.tap(find.text(lang.tr('tabUpdate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify OTA tab controls are present
      expect(find.byKey(const ValueKey('ota-check-button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ota-server-path-input')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ota-interval-dropdown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ota-test-connection-button')),
        findsOneWidget,
      );
    });

    testWidgets(
      'GlassUpdateDialog displays version, size, changelog and action buttons',
      (tester) async {
        tester.view.physicalSize = const Size(800, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final packageInfo = UpdatePackageInfo(
          version: SemanticVersion.tryParse('1.3.0')!,
          fileName: 'JA_LAN_Messenger_v1.3.0_Windows_x64.zip',
          fullPath: '/mock/update.zip',
          fileSize: 15 * 1024 * 1024,
          releaseNotes: '- Bổ sung cập nhật OTA\n- Sửa lỗi kết nối mạng',
          releaseDate: DateTime(2026, 9, 19),
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
              ChangeNotifierProvider.value(value: coordinator),
            ],
            child: MaterialApp(
              home: Scaffold(body: GlassUpdateDialog(packageInfo: packageInfo)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check version text
        expect(find.text('v1.3.0'), findsOneWidget);
        expect(find.text('v$appVersion'), findsOneWidget);
        // Check release notes text
        expect(find.textContaining('Bổ sung cập nhật OTA'), findsOneWidget);
        // Check action buttons
        expect(find.byKey(const ValueKey('btn-update-now')), findsOneWidget);
        expect(find.byKey(const ValueKey('btn-update-later')), findsOneWidget);
      },
    );
  });
}
