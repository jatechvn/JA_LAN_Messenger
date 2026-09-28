import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/autostart_service.dart';

void main() {
  late File prefs;
  late List<bool> calls;
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('autostart_default_');
    prefs = File('${dir.path}/preferences.json');
    calls = [];
  });
  Future<void> initialize({bool success = true, bool windows = true}) =>
      AutostartService.ensureDefaultForNewInstallation(
        preferencesFile: prefs,
        windows: windows,
        register: (enabled) async {
          calls.add(enabled);
          return success;
        },
      );
  test(
    'fresh installation enables once even if startup is later disabled',
    () async {
      await initialize();
      expect(calls, [true]);
      expect(await prefs.exists(), isFalse);
      await initialize();
      expect(calls, [true]);
    },
  );
  test('legacy preferences without startup setting are preserved', () async {
    await prefs.writeAsString('{"localNickname":"Johnny"}');
    await initialize();
    expect(calls, isEmpty);
    expect(await prefs.readAsString(), '{"localNickname":"Johnny"}');
  });
  test('failed registration does not record success', () async {
    await initialize(success: false);
    expect(await File('${prefs.path}.autostart-initialized').exists(), isFalse);
    await initialize();
    expect(calls, [true, true]);
  });
  test('other platforms do not register', () async {
    await initialize(windows: false);
    expect(calls, isEmpty);
  });
}
