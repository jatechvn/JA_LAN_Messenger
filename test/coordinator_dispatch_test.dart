import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

class _UnusedSocket extends Fake implements Socket {}

class _NavigationCoordinator extends MessengerCoordinator {
  _NavigationCoordinator({required super.knownDevices});

  final navigationPeers = <PeerModel>[];
  final selections = <PeerModel?>[];

  @override
  List<PeerModel> get peers => navigationPeers;

  @override
  void selectPeer(PeerModel? peer) {
    selections.add(peer);
    super.selectPeer(peer);
  }
}

class _CallbackCoordinator extends MessengerCoordinator {
  _CallbackCoordinator({required super.tcpServer, required super.knownDevices});

  final calls = <String, List<Object?>>{};

  @override
  void handlePeerActivity(String endpoint) => calls['activity'] = [endpoint];

  @override
  void handlePeerDisconnected(String endpoint) =>
      calls['disconnected'] = [endpoint];

  @override
  void handlePeerStatus(String endpoint, Map<String, dynamic> message) =>
      calls['status'] = [endpoint, message];

  @override
  void handlePeerHandshake(
    String senderIp,
    Map<String, dynamic> data,
    Socket socket,
  ) => calls['handshake'] = [senderIp, data, socket];

  @override
  void handleIncomingMessage(
    String senderIp,
    String messageId,
    String text,
    DateTime timestamp, {
    String? groupId,
  }) => calls['message'] = [senderIp, messageId, text, timestamp, groupId];

  @override
  void handleGroupPacket(String endpoint, Map<String, dynamic> message) =>
      calls['group'] = [endpoint, message];

  @override
  void handleGroupMessage(String endpoint, Map<String, dynamic> message) =>
      calls['groupMessage'] = [endpoint, message];

  @override
  void handleIncomingBuzz(String senderIp) => calls['buzz'] = [senderIp];

  @override
  void handleIncomingReaction(
    String endpoint,
    String messageId,
    String emoji,
    String action,
    String senderName,
  ) => calls['reaction'] = [endpoint, messageId, emoji, action, senderName];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final coordinators = <MessengerCoordinator>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ja_dispatch_test_');
    AppPreferences().setCustomFileForTesting(
      File('${directory.path}/preferences.json'),
    );
    await AppPreferences().load();
    ChatHistoryService().setCustomDirectoryForTesting(
      Directory('${directory.path}/history')..createSync(),
    );
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${directory.path}/groups.json',
    );
  });

  tearDown(() async {
    for (final coordinator in coordinators) {
      coordinator.dispose();
    }
    coordinators.clear();
    await ChatHistoryService().flush();
    AppPreferences().setCustomFileForTesting(null);
    ChatHistoryService().setCustomDirectoryForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
  });

  KnownDevicesRegistry devices() =>
      KnownDevicesRegistry('${directory.path}/devices.json');

  test(
    'TCP callbacks wired by constructor dispatch to subclass overrides',
    () async {
      final server = LanTcpServer();
      final coordinator = _CallbackCoordinator(
        tcpServer: server,
        knownDevices: devices(),
      );
      coordinators.add(coordinator);
      await coordinator.historyLoaded;
      const endpoint = '192.0.2.1:6475';
      final payload = <String, dynamic>{'id': 'packet'};
      final socket = _UnusedSocket();
      final timestamp = DateTime(2026, 11, 16);

      server.onActivity!(endpoint);
      expect(coordinator.calls['activity'], [endpoint]);
      server.onDisconnected!(endpoint);
      server.onUserStatus!(endpoint, payload);
      server.onHandshake!(endpoint, payload, socket);
      server.onMessage!(endpoint, '42', 'hello', timestamp);
      server.onGroup!(endpoint, payload);
      server.onGroupMessage!(endpoint, payload);
      server.onBuzz!(endpoint);
      server.onReaction!(endpoint, '42', '👍', 'add', 'Alice');

      expect(coordinator.calls, {
        'activity': [endpoint],
        'disconnected': [endpoint],
        'status': [endpoint, payload],
        'handshake': [endpoint, payload, socket],
        'message': [endpoint, '42', 'hello', timestamp, null],
        'group': [endpoint, payload],
        'groupMessage': [endpoint, payload],
        'buzz': [endpoint],
        'reaction': [endpoint, '42', '👍', 'add', 'Alice'],
      });
    },
  );

  test('dynamic invocation reaches real methods and getters', () async {
    final coordinator = MessengerCoordinator(knownDevices: devices());
    coordinators.add(coordinator);
    await coordinator.historyLoaded;
    final dynamic api = coordinator;
    final peer = PeerModel(id: 'alice', name: 'Alice', ip: '192.0.2.1');

    api.selectPeer(peer);
    api.setSearchQuery('Alice');
    expect(api.selectedPeer, same(peer));
    expect(api.searchQuery, 'Alice');
    expect(api.currentMessages, isEmpty);
    expect(api.fileTasks, isEmpty);
    expect(api.getPinnedMessages(peer.id), isEmpty);
    expect(api.availableAiModels, coordinator.availableAiModels);
    api.selectPeer(null);
    expect(api.selectedPeer, isNull);
  });

  test(
    'tear-offs, super calls and internal navigation retain virtual dispatch',
    () async {
      final coordinator = _NavigationCoordinator(knownDevices: devices());
      coordinators.add(coordinator);
      await coordinator.historyLoaded;
      final alice = PeerModel(id: 'alice', name: 'Alice', ip: '192.0.2.1');
      final bob = PeerModel(id: 'bob', name: 'Bob', ip: '192.0.2.2');
      coordinator.navigationPeers.addAll([alice, bob]);
      final MessengerCoordinator base = coordinator;
      final void Function(PeerModel?) choose = base.selectPeer;
      var notifications = 0;
      base.addListener(() => notifications++);

      choose(alice);
      expect(base.selectedPeer, same(alice));
      expect(notifications, 1);
      // selectAdjacentPeer's private implementation must read the overridden
      // peers getter and call the overridden selectPeer method, then super.
      base.selectAdjacentPeer(1);
      expect(base.selectedPeer, same(bob));
      expect(coordinator.selections, [alice, bob]);
      expect(notifications, 2);

      final dynamic api = base;
      api.selectPeer(null);
      expect(coordinator.selections, [alice, bob, null]);
      expect(base.selectedPeer, isNull);
      expect(notifications, 3);
    },
  );

  test(
    'wrappers preserve optional arguments and asynchronous results',
    () async {
      final coordinator = MessengerCoordinator(knownDevices: devices());
      coordinators.add(coordinator);
      await coordinator.historyLoaded;
      final dynamic api = coordinator;

      final PeerModel standard = api.addOfflineManualPeer('192.0.2.10');
      final PeerModel custom = api.addOfflineManualPeer('192.0.2.11', 6500);
      expect(standard.port, 6475);
      expect(custom.port, 6500);

      final Future<ManualPeerResult> defaultResult = api.addManualPeer(
        'invalid',
      );
      expect((await defaultResult).status, ManualAddStatus.invalidIp);
      final Future<ManualPeerResult> explicitResult = api.addManualEndpoint(
        'invalid',
        6500,
      );
      expect((await explicitResult).status, ManualAddStatus.invalidIp);

      api.setPeerTypingForTesting(standard.id, true);
      expect(api.isPeerTyping(standard.id), isTrue);
      api.setPeerTypingForTesting(standard.id, false);
      expect(api.isPeerTyping(standard.id), isFalse);
    },
  );
}
