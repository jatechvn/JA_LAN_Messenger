import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
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
  Completer<bool>? connection;
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
  @override
  Future<bool> connect(
    String ip,
    int port, {
    String? sourceAddress,
    Duration timeout = const Duration(seconds: 5),
  }) async => connection == null ? false : connection!.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File prefFile;
  late _TestLanTcpServer server;
  late MessengerCoordinator coordinator;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_retry_test_');
    prefFile = File('${tempDir.path}/prefs.json');
    AppPreferences().setCustomFileForTesting(prefFile);
    await AppPreferences().load();
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${tempDir.path}/groups.json',
    );

    server = _TestLanTcpServer();
    ChatHistoryService().setCustomDirectoryForTesting(
      Directory('${tempDir.path}/history')..createSync(),
    );
    coordinator = MessengerCoordinator(
      tcpServer: server,
      knownDevices: KnownDevicesRegistry('${tempDir.path}/devices.json'),
    );
    await coordinator.historyLoaded;
  });

  tearDown(() async {
    coordinator.dispose();
    await ChatHistoryService().flush();
    ChatHistoryService().setCustomDirectoryForTesting(null);
    AppPreferences().setCustomFileForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
  });

  group('Offline Message Outbox & Auto-Retry Tests', () {
    PeerModel connectPeer(String ip) {
      coordinator.handlePeerHandshake(ip, {
        'port': 6475,
        'username': ip,
        'hostname': 'test-$ip',
      }, _MockSocket());
      return coordinator.peers.firstWhere((p) => p.ip == ip);
    }

    int sentText(String value) => server.sentPackets
        .where((p) => ProtocolBeebeep.parseMessage(p.raw)?['text'] == value)
        .length;

    test('concurrent automatic flushes send each message once', () async {
      final peer = connectPeer('192.0.2.10');
      coordinator.selectPeer(peer);
      await coordinator.sendMessage('only once');
      server.canSend = true;
      await Future.wait([
        coordinator.flushPendingOutgoingMessagesForPeer(peer),
        coordinator.flushPendingOutgoingMessagesForPeer(peer),
      ]);
      expect(sentText('only once'), 1);
    });

    test(
      'manual connect and handshake flush cannot duplicate a message',
      () async {
        final peer = connectPeer('192.0.2.10');
        coordinator.selectPeer(peer);
        await coordinator.sendMessage('manual overlap');
        server.connection = Completer<bool>();
        final manual = coordinator.retrySendMessage(
          coordinator.currentMessages.single,
        );
        await Future<void>.delayed(Duration.zero);
        server.canSend = true;
        final auto = coordinator.flushPendingOutgoingMessagesForPeer(peer);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        server.connection!.complete(true);
        await Future.wait([manual, auto]);
        expect(sentText('manual overlap'), 1);
      },
    );

    test('removing a member during delayed flush prevents delivery', () async {
      final a = connectPeer('192.0.2.10');
      await coordinator.createGroup('Team', [a.id]);
      await coordinator.sendMessage('not for removed member');
      server.canSend = true;
      final sending = coordinator.flushPendingOutgoingMessagesForPeer(a);
      coordinator.removeGroupMember(coordinator.groups.single.id, a.id);
      await sending;
      expect(sentText('not for removed member'), 0);
    });

    test('failed broadcast delivery retries with broadcast framing', () async {
      final a = connectPeer('192.0.2.10');
      coordinator.selectPeer(coordinator.allUsersPeer);
      await coordinator.sendMessage('broadcast retry');
      server.canSend = true;
      await coordinator.flushPendingOutgoingMessagesForPeer(a);
      expect(sentText('[All Users] broadcast retry'), 1);
      expect(coordinator.currentMessages.single.pendingRecipients, isEmpty);
    });

    test('revoking during flush delay cancels the pending send', () async {
      final peer = connectPeer('192.0.2.10');
      coordinator.selectPeer(peer);
      await coordinator.sendMessage('cancel me');
      final msg = coordinator.currentMessages.single;
      server.canSend = true;
      final sending = coordinator.flushPendingOutgoingMessagesForPeer(peer);
      msg.isRevoked = true;
      await sending;
      expect(sentText('cancel me'), 0);
    });

    test('partial group outbox survives real coordinator restart', () async {
      final a = connectPeer('192.0.2.10');
      final b = connectPeer('192.0.2.11');
      b.status = PeerStatus.offline;
      await coordinator.createGroup('Team', [a.id, b.id]);
      final groupId = coordinator.groups.single.id;
      server.canSend = true;
      await coordinator.sendMessage('persist group');
      expect(coordinator.currentMessages.single.status, MessageStatus.sent);
      await coordinator.chatHistory.flush();
      coordinator.dispose();
      coordinator = MessengerCoordinator(
        tcpServer: server,
        knownDevices: KnownDevicesRegistry(
          '${tempDir.path}/restart-devices.json',
        ),
      );
      await coordinator.historyLoaded;
      expect(coordinator.pendingOfflineMessageIds[b.id], isNotEmpty);
      final reconnected = connectPeer(b.ip);
      await coordinator.flushPendingOutgoingMessagesForPeer(reconnected);
      expect(sentText('persist group'), 2); // once to A, once to B
      expect(
        coordinator.conversationsMap[groupId]!.single.pendingRecipients,
        isEmpty,
      );
    });

    test('manual group retry clears only successful recipients', () async {
      final a = connectPeer('192.0.2.10');
      final b = connectPeer('192.0.2.11');
      await coordinator.createGroup('Team', [a.id, b.id]);
      await coordinator.sendMessage('group retry');
      final msg = coordinator.currentMessages.single;
      b.status = PeerStatus.offline;
      server.canSend = true;
      expect(await coordinator.retrySendMessage(msg), isTrue);
      expect(msg.pendingRecipients, {b.id});
      await coordinator.flushPendingOutgoingMessagesForPeer(a);
      expect(sentText('group retry'), 1);
      b.status = PeerStatus.online;
      await coordinator.flushPendingOutgoingMessagesForPeer(b);
      expect(sentText('group retry'), 2);
    });

    test('failed attachments never retry as plain chat text', () async {
      final peer = connectPeer('192.0.2.10');
      final attachment = MessageModel(
        id: 'file',
        senderId: 'me',
        senderName: 'Me',
        recipientId: peer.id,
        text: 'private file path',
        isMine: true,
        status: MessageStatus.failed,
        fileAttachment: const FileAttachmentInfo(
          fileName: 'file.txt',
          fileSize: 1,
        ),
      );
      await coordinator.chatHistory.saveImmediately(peer.id, [attachment]);
      coordinator.dispose();
      coordinator = MessengerCoordinator(
        tcpServer: server,
        knownDevices: KnownDevicesRegistry(
          '${tempDir.path}/restart-devices.json',
        ),
      );
      await coordinator.historyLoaded;
      final loaded = coordinator.conversationsMap[peer.id]!.single;
      expect(coordinator.canRetryMessage(loaded), isFalse);
      server.canSend = true;
      expect(await coordinator.retrySendMessage(loaded), isFalse);
      await coordinator.flushPendingOutgoingMessagesForPeer(peer);
      expect(sentText('private file path'), 0);
    });

    test(
      'Sending to offline peer marks message as failed and enqueues to outbox',
      () async {
        final peer = PeerModel(
          id: '192.168.1.100:64738',
          name: 'Bob',
          ip: '192.168.1.100',
          port: 64738,
          status: PeerStatus.offline,
        );
        coordinator.selectPeer(peer);

        // Server is offline
        server.canSend = false;

        final success = await coordinator.sendMessage('Hello offline Bob');
        expect(success, isFalse);

        final conversation = coordinator.conversationsMap[peer.id];
        expect(conversation, isNotNull);
        expect(conversation!.length, equals(1));

        final msg = conversation.first;
        expect(msg.status, equals(MessageStatus.failed));
        expect(msg.text, equals('Hello offline Bob'));

        // Check that message ID is recorded in outbox
        expect(coordinator.pendingOfflineMessageIds[peer.id], isNotNull);
        expect(
          coordinator.pendingOfflineMessageIds[peer.id]!.contains(msg.id),
          isTrue,
        );
      },
    );

    test(
      'flushPendingOutgoingMessagesForPeer automatically retries and marks sent when peer comes online',
      () async {
        final peer = PeerModel(
          id: '192.168.1.100:64738',
          name: 'Bob',
          ip: '192.168.1.100',
          port: 64738,
          status: PeerStatus.offline,
        );
        coordinator.selectPeer(peer);

        // Step 1: Send message when peer is offline
        server.canSend = false;
        await coordinator.sendMessage('Urgent offline message');

        final msg = coordinator.conversationsMap[peer.id]!.first;
        expect(msg.status, equals(MessageStatus.failed));

        // Step 2: Peer comes online, server can now send
        server.canSend = true;
        peer.status = PeerStatus.online;

        // Trigger outbox flush
        await coordinator.flushPendingOutgoingMessagesForPeer(peer);

        // Message status should transition to sent
        expect(msg.status, equals(MessageStatus.sent));

        // Outbox queue should be cleaned up
        final remaining = coordinator.pendingOfflineMessageIds[peer.id];
        expect(remaining == null || remaining.isEmpty, isTrue);

        // Packet was sent over the wire
        expect(server.sentPackets, isNotEmpty);
        expect(server.sentPackets.last.raw, contains('Urgent offline message'));
      },
    );

    test('retrySendMessage manually resends failed message', () async {
      final peer = PeerModel(
        id: '192.168.1.100:64738',
        name: 'Bob',
        ip: '192.168.1.100',
        port: 64738,
      );
      coordinator.selectPeer(peer);

      // Initial failed send
      server.canSend = false;
      await coordinator.sendMessage('Try sending this');

      final msg = coordinator.conversationsMap[peer.id]!.first;
      expect(msg.status, equals(MessageStatus.failed));

      // Now connection is restored
      server.canSend = true;

      // Manual retry
      final retryOk = await coordinator.retrySendMessage(msg);
      expect(retryOk, isTrue);
      expect(msg.status, equals(MessageStatus.sent));
      expect(server.sentPackets, isNotEmpty);
    });

    test(
      'Group chat tracks offline members in outbox and flushes on reconnect',
      () async {
        final memberA = PeerModel(
          id: '192.168.1.101:64738',
          name: 'Alice',
          ip: '192.168.1.101',
          port: 64738,
          status: PeerStatus.online,
        );
        final memberB = PeerModel(
          id: '192.168.1.102:64738',
          name: 'Charlie',
          ip: '192.168.1.102',
          port: 64738,
          status: PeerStatus.offline,
        );

        coordinator.handlePeerHandshake(memberA.ip, {
          'port': memberA.port,
          'username': memberA.name,
          'hostname': 'Alice-PC',
        }, _MockSocket());

        await coordinator.createGroup('Dev Team', [memberA.id, memberB.id]);
        final group = coordinator.groups.first;
        coordinator.selectPeer(PeerModel.fromGroup(group));

        // Alice receives, but Charlie is offline
        server.canSend = true;
        final ok = await coordinator.sendMessage('Team update');
        expect(ok, isTrue); // Alice got it

        // Charlie should be tracked in outbox for this message
        expect(coordinator.pendingOfflineMessageIds[memberB.id], isNotNull);
        expect(coordinator.pendingOfflineMessageIds[memberB.id], isNotEmpty);

        // Now Charlie connects and comes online
        coordinator.handlePeerHandshake(memberB.ip, {
          'port': memberB.port,
          'username': memberB.name,
          'hostname': 'Charlie-PC',
        }, _MockSocket());

        await coordinator.flushPendingOutgoingMessagesForPeer(memberB);

        // Charlie's pending outbox should be cleared
        final remaining = coordinator.pendingOfflineMessageIds[memberB.id];
        expect(remaining == null || remaining.isEmpty, isTrue);
      },
    );

    test(
      'Localization keys for retry and offline failed tooltips are present in VI, EN, ZH',
      () {
        final lang = LanguageProvider();
        addTearDown(lang.dispose);

        for (final code in ['vi', 'en', 'zh']) {
          lang.setLanguage(AppLanguage.fromCode(code));
          expect(lang.tr('retrySend'), isNotEmpty);
          expect(lang.tr('retrySend'), isNot('retrySend'));
          expect(
            lang.tr('messageFailedTooltip'),
            isNot('messageFailedTooltip'),
          );
          expect(
            lang.tr('messageResentSuccess'),
            isNot('messageResentSuccess'),
          );
          expect(lang.tr('messageFailedTooltip'), isNotEmpty);
          expect(lang.tr('messageResentSuccess'), isNotEmpty);
        }
      },
    );

    test(
      'Chat history reloads failed and sending messages into outbox queue',
      () async {
        final historyDir = Directory('${tempDir.path}/history');
        await historyDir.create(recursive: true);
        coordinator.chatHistory.setCustomDirectoryForTesting(historyDir);

        final msg1 = MessageModel(
          id: 'msg_persisted_failed_001',
          senderId: 'me',
          senderName: 'Me',
          recipientId: '192.168.1.105:64738',
          text: 'Failed message',
          status: MessageStatus.failed,
          isMine: true,
        );
        final msg2 = MessageModel(
          id: 'msg_persisted_sending_002',
          senderId: 'me',
          senderName: 'Me',
          recipientId: '192.168.1.105:64738',
          text: 'Interrupted message',
          status: MessageStatus.sending, // will normalize to failed
          isMine: true,
        );

        await coordinator.chatHistory.saveImmediately('192.168.1.105:64738', [
          msg1,
          msg2,
        ]);

        // Create new coordinator that loads history from this directory
        final coordinator2 = MessengerCoordinator(
          tcpServer: server,
          knownDevices: KnownDevicesRegistry('${tempDir.path}/devices2.json'),
        );
        addTearDown(coordinator2.dispose);
        await coordinator2.historyLoaded;

        final outbox =
            coordinator2.pendingOfflineMessageIds['192.168.1.105:64738'];
        expect(outbox, isNotNull);
        expect(outbox!.contains('msg_persisted_failed_001'), isTrue);
        expect(outbox.contains('msg_persisted_sending_002'), isTrue);
      },
    );
  });
}
