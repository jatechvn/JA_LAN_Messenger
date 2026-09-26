import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

class _MockSocket implements Socket {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLanTcpServer extends LanTcpServer {
  bool canSend = false;
  final List<({String endpoint, String raw})> sentPackets = [];

  @override
  bool send(String endpoint, List<int> packet) {
    if (!canSend) return false;
    final text = utf8.decode(packet);
    sentPackets.add((endpoint: endpoint, raw: text));
    return true;
  }

  @override
  bool isConnected(String endpoint) => canSend;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File prefFile;
  late _TestLanTcpServer server;
  late MessengerCoordinator coordinator;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_ack_retry_test_');
    prefFile = File('${tempDir.path}/prefs.json');
    AppPreferences().setCustomFileForTesting(prefFile);
    await AppPreferences().load();
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${tempDir.path}/groups.json',
    );

    final historyDir = Directory('${tempDir.path}/conversations')
      ..createSync(recursive: true);
    ChatHistoryService().setCustomDirectoryForTesting(historyDir);

    server = _TestLanTcpServer();
    coordinator = MessengerCoordinator(
      tcpServer: server,
      knownDevices: KnownDevicesRegistry('${tempDir.path}/known_devices.json'),
    );
    await coordinator.historyLoaded;
  });

  tearDown(() async {
    await coordinator.chatHistory.flush();
    coordinator.dispose();
    ChatHistoryService().setCustomDirectoryForTesting(null);
    AppPreferences().setCustomFileForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Offline Disconnect, Outbox Queue, & Delivery ACK Verification Tests', () {
    test(
      'Messages sent to offline peer immediately transition to failed and queue in outbox',
      () async {
        final peer = PeerModel(
          id: '172.21.174.103:6475',
          name: 'Bob',
          ip: '172.21.174.103',
          port: 6475,
          status: PeerStatus.offline,
        );
        coordinator.selectPeer(peer);

        server.canSend = false;
        final ok = await coordinator.sendMessage('Hello offline');
        expect(ok, isFalse);

        final msg = coordinator.currentMessages.first;
        expect(msg.status, MessageStatus.failed);
        expect(coordinator.pendingOfflineMessageIds[peer.id], contains(msg.id));
      },
    );

    test(
      'Unconfirmed "sent" message transitions to failed and queues in Outbox upon remote disconnect',
      () async {
        // Step 1: Peer connects and handshakes
        coordinator.handlePeerHandshake('172.21.174.103', {
          'username': 'Bob',
          'account': 'bob',
          'hostname': 'PC-BOB',
          'port': 6475,
        }, _MockSocket());

        final peer = coordinator.peersMap['172.21.174.103:6475']!;
        expect(peer.status, isNot(PeerStatus.offline));
        coordinator.selectPeer(peer);

        // Step 2: Message sent while connection thought to be open
        server.canSend = true;
        await coordinator.sendMessage('Testing unconfirmed message');
        final msg = coordinator.currentMessages.first;
        expect(msg.status, MessageStatus.sent);

        // Step 3: Remote app exits, TCP connection breaks before delivery ACK arrives
        server.canSend = false;
        coordinator.handlePeerDisconnected('172.21.174.103:6475');

        // Message MUST NOT be left as false-positive "sent"!
        // It must transition to failed and be registered in Outbox!
        expect(peer.status, PeerStatus.offline);
        expect(msg.status, MessageStatus.failed);
        expect(coordinator.pendingOfflineMessageIds[peer.id], contains(msg.id));

        // Step 4: Remote app reopens and handshakes
        coordinator.handlePeerHandshake('172.21.174.103', {
          'username': 'Bob',
          'account': 'bob',
          'hostname': 'PC-BOB',
          'port': 6475,
        }, _MockSocket());

        // Step 5: Flush outbox
        server.sentPackets.clear();
        server.canSend = true;
        await coordinator.flushPendingOutgoingMessagesForPeer(peer);

        // Packet resent over the wire
        expect(server.sentPackets, isNotEmpty);
        expect(server.sentPackets.last.raw, contains('Testing unconfirmed message'));
        expect(msg.status, MessageStatus.sent);

        // Step 6: Recipient sends ACK (headerRecv)
        server.onAck?.call('172.21.174.103:6475', msg.id);
        expect(msg.status, MessageStatus.delivered);
        expect(
          coordinator.pendingOfflineMessageIds[peer.id]?.contains(msg.id) ?? false,
          isFalse,
        );
      },
    );

    test(
      'Recipient side: incoming message unifies with history-only peer loaded from disk',
      () async {
        // Step 1: Save historical conversation to disk
        await coordinator.chatHistory.saveImmediately('172.21.174.102', [
          MessageModel(
            id: 'old-1',
            senderId: '172.21.174.102',
            senderName: 'Alice',
            recipientId: 'me',
            text: 'Old message',
            timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
            isMine: false,
            status: MessageStatus.read,
          ),
        ]);
        await coordinator.chatHistory.flush();

        // Step 2: Restart coordinator to simulate fresh app launch
        coordinator.dispose();
        coordinator = MessengerCoordinator(
          tcpServer: server,
          knownDevices: KnownDevicesRegistry('${tempDir.path}/known_devices.json'),
        );
        await coordinator.historyLoaded;

        // Step 3: Incoming message arrives from 172.21.174.102:6475
        coordinator.handleIncomingMessage(
          '172.21.174.102:6475',
          'new-1',
          'Hello from flushed outbox',
          DateTime.now(),
        );

        // Find peer by IP or ID
        final peer = coordinator.peers.firstWhere(
          (p) => p.ip == '172.21.174.102',
        );
        coordinator.selectPeer(peer);

        // The unified chat must contain BOTH the old and new incoming message!
        final texts = coordinator.currentMessages.map((m) => m.text).toList();
        expect(texts, contains('Old message'));
        expect(texts, contains('Hello from flushed outbox'));
      },
    );
  });
}
