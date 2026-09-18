import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';

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
