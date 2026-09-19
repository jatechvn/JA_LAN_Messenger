import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/logger_config.dart';

void main() {
  test('Logger writes startup marker in isolated local app data', () async {
    final root = Platform.environment['LOCALAPPDATA']!;
    // This test must be invoked with an explicitly isolated environment.
    if (!root.contains('ja-preview-')) return;
    setupLogger();
    await Future<void>.delayed(Duration.zero);
    disposeLogger();
    final logs = Directory(
      '$root/JA_LAN_Messenger/logs',
    ).listSync().whereType<File>();
    expect(
      logs.any((file) => file.readAsStringSync().contains('app_started mode=')),
      true,
    );
  });
}
