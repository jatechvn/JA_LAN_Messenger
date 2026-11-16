import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/ai_server_locator.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

class ControlledLocator extends AiServerLocator {
  final result = Completer<Uri?>();
  int calls = 0;
  @override
  Future<Uri?> locate(
    Uri old,
    List<String> subnets, {
    Iterable<PeerModel> peers = const [],
    bool Function()? cancelled,
  }) {
    calls++;
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final latePeer in [false, true]) {
    test('BeeBEEP AI peer recovers without DNS, late peer=$latePeer', () async {
      final dir = await Directory.systemTemp.createTemp('ai_beebeep_');
      final prefs = AppPreferences()
        ..setCustomFileForTesting(File('${dir.path}/prefs.json'));
      await prefs.load();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        request.response.write('{"models":[]}');
        await request.response.close();
      });
      final oldUrl = 'http://192.0.2.1:${server.port}/ollama';
      await prefs.setAiConfig(serverUrl: oldUrl);
      ChatHistoryService().setCustomDirectoryForTesting(
        Directory('${dir.path}/history')..createSync(),
      );
      MessengerCoordinator.customGroupsFileForTesting = File(
        '${dir.path}/groups.json',
      );
      final c = MessengerCoordinator(
        knownDevices: KnownDevicesRegistry('${dir.path}/devices.json'),
        aiServerLocator: AiServerLocator(
          resolve: (_) async => [],
          multicastResolve: (_) async => [],
        ),
      );
      addTearDown(() async {
        c.dispose();
        await server.close(force: true);
        ChatHistoryService().setCustomDirectoryForTesting(null);
        MessengerCoordinator.customGroupsFileForTesting = null;
        prefs.setCustomFileForTesting(null);
      });
      await c.historyLoaded;
      if (latePeer) {
        expect(await c.aiService.recoverConnection!(oldUrl), isFalse);
      }
      final peer = PeerModel(
        id: '127.0.0.1:6475',
        name: 'JA-AI-SERVER',
        hostname: AiServerLocator.machineName,
        ip: '127.0.0.1',
        isBeebeep: true,
      );
      c.peersMap[peer.id] = peer;
      c.setSearchQuery('some unrelated contact');
      expect(
        await HttpOverrides.runWithHttpOverrides(
          () => c.aiService.recoverConnection!(oldUrl),
          _LoopbackHttpOverrides(),
        ),
        isTrue,
      );
      expect(paths, ['/ollama/api/tags']);
      expect(prefs.aiServerUrl, 'http://127.0.0.1:${server.port}/ollama');
      expect(c.aiService.serverUrl, prefs.aiServerUrl);
      expect(c.currentToast!.key, 'aiScanRecovered');
      final saved = jsonDecode(await prefs.preferencesFile.readAsString());
      expect(saved['aiServerUrl'], prefs.aiServerUrl);
    });
  }
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
        expect(
          await c.aiService.recoverConnection!(prefs.aiServerUrl),
          isFalse,
        );
        expect(
          locator.calls,
          1,
          reason: 'Unchanged failures retain the cooldown',
        );
      }
    });
  }
}
