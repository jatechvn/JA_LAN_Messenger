import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/ai_server_locator.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

class ControlledLocator extends AiServerLocator {
  final result = Completer<Uri?>();
  int calls = 0;
  @override
  Future<Uri?> locate(
    Uri old,
    List<String> subnets, {
    bool Function()? cancelled,
  }) {
    calls++;
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in ['success', 'notFound', 'error', 'changed', 'disposed']) {
    test('coordinator recovery $mode guards config and notifies', () async {
      final dir = await Directory.systemTemp.createTemp('ai_recovery_');
      final prefsFile = File('${dir.path}/prefs.json');
      final prefs = AppPreferences()..setCustomFileForTesting(prefsFile);
      await prefs.load();
      await prefs.setAiConfig(serverUrl: 'http://192.0.2.1:11434');
      ChatHistoryService().setCustomDirectoryForTesting(
        Directory('${dir.path}/history')..createSync(),
      );
      MessengerCoordinator.customGroupsFileForTesting = File(
        '${dir.path}/groups.json',
      );
      final locator = ControlledLocator();
      final c = MessengerCoordinator(
        aiServerLocator: locator,
        knownDevices: KnownDevicesRegistry('${dir.path}/devices.json'),
      );
      await c.historyLoaded;
      var disposed = false;
      addTearDown(() {
        if (!disposed) c.dispose();
        ChatHistoryService().setCustomDirectoryForTesting(null);
        MessengerCoordinator.customGroupsFileForTesting = null;
        prefs.setCustomFileForTesting(null);
      });
      final first = c.aiService.recoverConnection!(prefs.aiServerUrl);
      final second = c.aiService.recoverConnection!(prefs.aiServerUrl);
      expect(locator.calls, 1);
      expect(c.currentToast!.key, 'aiScanSearching');
      if (mode == 'changed') {
        await prefs.setAiConfig(serverUrl: 'http://192.0.2.99:11434');
      }
      if (mode == 'disposed') {
        c.dispose();
        disposed = true;
      }
      if (mode == 'error') {
        locator.result.completeError(StateError('test scan error'));
      } else {
        locator.result.complete(
          mode == 'notFound' ? null : Uri.parse('http://192.0.2.2:11434'),
        );
      }
      expect(await first, mode == 'success' || mode == 'changed');
      await second;
      if (mode == 'success') {
        expect(prefs.aiServerUrl, 'http://192.0.2.2:11434');
        expect(
          jsonDecode(await prefsFile.readAsString())['aiServerUrl'],
          prefs.aiServerUrl,
        );
        expect(c.currentToast!.key, 'aiScanRecovered');
      } else if (mode == 'changed') {
        expect(prefs.aiServerUrl, 'http://192.0.2.99:11434');
      } else if (mode == 'notFound' || mode == 'error') {
        expect(prefs.aiServerUrl, 'http://192.0.2.1:11434');
        expect(
          c.currentToast!.key,
          mode == 'error' ? 'aiScanFailed' : 'aiScanNotFound',
        );
      }
    });
  }
}
