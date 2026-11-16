import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';

class _DelayedReadFile extends Fake implements File {
  _DelayedReadFile(this.file);
  final File file;
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool _firstRead = true;

  @override
  String get path => file.path;

  @override
  Future<bool> exists() => file.exists();

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    final content = await file.readAsString(encoding: encoding);
    if (_firstRead) {
      _firstRead = false;
      readStarted.complete();
      await releaseRead.future;
    }
    return content;
  }
}

void main() {
  late Directory tempDir;
  late File tempFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ja_pref_test_');
    tempFile = File('${tempDir.path}/user_preferences.json');
    AppPreferences().setCustomFileForTesting(tempFile);
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('AppPreferences defaults to ask and remember=false', () async {
    final prefs = AppPreferences();
    expect(prefs.closeBehavior, 'ask');
    expect(prefs.rememberCloseBehavior, false);
  });

  test(
    'startup OTA settings save preserves close choice while load is pending',
    () async {
      await tempFile.writeAsString(
        jsonEncode({
          'closeBehavior': 'minimize',
          'rememberCloseBehavior': true,
        }),
      );
      final delayed = _DelayedReadFile(tempFile);
      final prefs = AppPreferences()..setCustomFileForTesting(delayed);
      final loading = prefs.load();
      await delayed.readStarted.future;
      try {
        await prefs.setOtaSettings(checkInterval: 'weekly');
      } finally {
        delayed.releaseRead.complete();
        await loading;
      }
      prefs.setCustomFileForTesting(tempFile);
      await prefs.load();
      expect(prefs.closeBehavior, 'minimize');
      expect(prefs.rememberCloseBehavior, isTrue);
      expect(prefs.otaCheckInterval, 'weekly');
    },
  );

  test(
    'settings close selection persists without a separate remember checkbox',
    () async {
      final prefs = AppPreferences();
      await prefs.setCloseBehavior('minimize');
      prefs.setCustomFileForTesting(tempFile);
      await prefs.load();
      expect(prefs.closeBehavior, 'minimize');
      expect(prefs.rememberCloseBehavior, isTrue);
      await prefs.setCloseBehavior('ask');
      expect(prefs.rememberCloseBehavior, isFalse);
    },
  );

  test('explicit close choice wins over an older delayed load', () async {
    await tempFile.writeAsString(
      jsonEncode({'closeBehavior': 'minimize', 'rememberCloseBehavior': true}),
    );
    final delayed = _DelayedReadFile(tempFile);
    final prefs = AppPreferences()..setCustomFileForTesting(delayed);
    final loading = prefs.load();
    await delayed.readStarted.future;
    try {
      await prefs.setCloseBehavior('exit', remember: false);
    } finally {
      delayed.releaseRead.complete();
      await loading;
    }
    prefs.setCustomFileForTesting(tempFile);
    await prefs.load();
    expect(prefs.closeBehavior, 'exit');
    expect(prefs.rememberCloseBehavior, isFalse);
  });
  test(
    'concurrent saves and flush preserve remembered tray choice on restart',
    () async {
      final prefs = AppPreferences();
      await Future.wait([
        prefs.setCloseBehavior('minimize', remember: true),
        prefs.setPeerPinned('peer-a', true),
        prefs.setPowerOptimization(
          enableIdleSleep: true,
          idleTimeoutSeconds: 30,
        ),
      ]);
      await prefs.flush();
      prefs.setCustomFileForTesting(tempFile);
      await prefs.load();
      expect(prefs.rememberCloseBehavior, isTrue);
      expect(prefs.closeBehavior, 'minimize');
      expect(prefs.idleTimeoutSeconds, 30);
      expect(File('${tempFile.path}.tmp').existsSync(), isFalse);
    },
  );

  test(
    'AppPreferences persists closeBehavior and rememberChoice across instances',
    () async {
      final prefs1 = AppPreferences();
      await prefs1.setCloseBehavior('minimize', remember: true);

      expect(prefs1.closeBehavior, 'minimize');
      expect(prefs1.rememberCloseBehavior, true);

      // Verify file written
      expect(await tempFile.exists(), true);

      // Verify second instance loads the saved preferences
      final prefs2 = AppPreferences();
      prefs2.setCustomFileForTesting(tempFile);
      await prefs2.load();

      expect(prefs2.closeBehavior, 'minimize');
      expect(prefs2.rememberCloseBehavior, true);
    },
  );

  test(
    'AppPreferences updates closeBehavior to exit without remember',
    () async {
      final prefs = AppPreferences();
      await prefs.setCloseBehavior('exit', remember: false);

      expect(prefs.closeBehavior, 'exit');
      expect(prefs.rememberCloseBehavior, false);
    },
  );
}
