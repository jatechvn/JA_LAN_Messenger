import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Nickname survives preferences reload and coordinator recreation',
    () async {
      final dir = await Directory.systemTemp.createTemp('ja-nickname-');
      final prefs = AppPreferences();
      prefs.setCustomFileForTesting(File('${dir.path}/preferences.json'));
      prefs.resetToDefaults();
      final first = MessengerCoordinator();
      await first.updateProfile(username: '  Johnny Nguyễn  ');
      expect(first.localUsername, 'Johnny Nguyễn');
      first.dispose();
      prefs.resetToDefaults();
      await prefs.load();
      final reopened = MessengerCoordinator();
      expect(reopened.localUsername, 'Johnny Nguyễn');
      await reopened.updateProfile(username: '   ');
      expect(reopened.localUsername, 'Johnny Nguyễn');
      reopened.dispose();
      prefs.setCustomFileForTesting(null);
      prefs.resetToDefaults();
    },
  );
}
