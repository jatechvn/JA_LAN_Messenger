import 'dart:io';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'group_sync_and_ui_test.dart' show RecordingServer, UnusedSocket, decode;

class _ReconnectServer extends RecordingServer {
  void Function()? connected;
  @override
  Future<bool> connect(
    String ip,
    int port, {
    String? sourceAddress,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    connected?.call();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late MessengerCoordinator c;
  late RecordingServer server;
  late KnownDevicesRegistry devices;
  Future<void> restart() async {
    await c.chatHistory.flush();
    c.dispose();
    c = MessengerCoordinator(tcpServer: server, knownDevices: devices);
    await c.historyLoaded;
  }

  void hello(
    String ip, {
    int port = 6475,
    bool bee = false,
    String account = 'alice',
    String host = 'PC-A',
  }) {
    c.handlePeerHandshake(ip, {
      'port': port,
      'account': account,
      'hostname': host,
      'username': account,
      'version': bee ? '5.8.4' : '1.4.0',
      'client': bee ? '' : 'JA_LAN_MESSENGER',
      'hash': '$account-${bee ? 'bee' : 'ja'}',
    }, UnusedSocket());
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('logical_sessions_');
    AppPreferences().setCustomFileForTesting(File('${dir.path}/prefs.json'));
    await AppPreferences().load();
    ChatHistoryService().setCustomDirectoryForTesting(
      Directory('${dir.path}/history')..createSync(),
    );
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${dir.path}/groups.json',
    );
    devices = KnownDevicesRegistry('${dir.path}/devices.json');
    server = RecordingServer();
    c = MessengerCoordinator(tcpServer: server, knownDevices: devices);
    await c.historyLoaded;
  });
  tearDown(() async {
    await c.chatHistory.flush();
    c.dispose();
    ChatHistoryService().setCustomDirectoryForTesting(null);
    AppPreferences().setCustomFileForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
  });

  test('unread attention total is independent of contact search', () {
    hello('192.0.2.1');
    hello('192.0.2.1', port: 6477, bee: true);
    c.peersMap['192.0.2.1:6475']!.unreadCount = 3;
    expect(c.totalUnreadCount, 3);
    c.setSearchQuery('no-such-contact');
    expect(c.peers, isEmpty);
    expect(c.totalUnreadCount, 3);
  });

  test(
    'online list excludes offline and shares search and session deduplication',
    () {
      hello('192.0.2.1');
      hello('192.0.2.1', port: 6477, bee: true);
      hello('192.0.2.2', account: 'bob', host: 'PC-B');
      hello('192.0.2.3', account: 'carol', host: 'PC-C');
      hello('192.0.2.4', account: 'dave', host: 'PC-D');
      c.peersMap['192.0.2.2:6475']!.status = PeerStatus.away;
      c.peersMap['192.0.2.3:6475']!.status = PeerStatus.busy;
      c.peersMap['192.0.2.4:6475']!.status = PeerStatus.offline;
      expect(c.onlinePeers.where((p) => !p.isAiAssistant), hasLength(3));
      expect(
        c.onlinePeers,
        c.peers.where((p) => p.status != PeerStatus.offline),
      );
      c.setSearchQuery('bob');
      expect(c.onlinePeers, hasLength(1));
      expect(c.onlinePeers.single.status, PeerStatus.away);
      c.setSearchQuery('dave');
      expect(c.peers, hasLength(1));
      expect(c.onlinePeers, isEmpty);
    },
  );

  test(
    'one conversation prefers JA independently of handshake order and falls back to Bee',
    () async {
      hello('192.0.2.1', bee: true);
      final peer = c.peersMap['192.0.2.1:6475']!;
      c.selectPeer(peer);
      hello('192.0.2.1', port: 6477);
      hello('192.0.2.1', bee: true);
      expect(c.peers.where((p) => !p.isAiAssistant), hasLength(1));
      expect(c.selectedPeer, same(peer));
      expect(peer.isBeebeep, isFalse);
      await c.sendMessage('prefer JA');
      expect(server.sent.last.endpoint, '192.0.2.1:6477');
      c.handlePeerDisconnected('192.0.2.1:6477');
      await c.sendMessage('fallback Bee');
      expect(server.sent.last.endpoint, '192.0.2.1:6475');
      expect(peer.isBeebeep, isTrue);
    },
  );

  test('persisted Buzz notices never enter chat retry on reconnect', () async {
    hello('192.0.2.1');
    final peer = c.peersMap['192.0.2.1:6475']!;
    final notices = [
      for (final id in ['buzz-sent-123', 'buzz-winrm-launching-456'])
        MessageModel(
          id: id,
          senderId: 'me',
          senderName: 'Me',
          recipientId: peer.id,
          text: 'local notice',
          isMine: true,
          status: MessageStatus.failed,
          pendingRecipients: {peer.id},
        ),
    ];
    c.conversationsMap[peer.id] = notices;
    await c.chatHistory.saveImmediately(peer.id, notices);
    await restart();
    hello('192.0.2.1');
    final restored = c.peersMap['192.0.2.1:6475']!;
    server.sent.clear();
    await c.flushPendingOutgoingMessagesForPeer(restored);
    expect(
      server.sent.where(
        (p) => p.message['header'] == ProtocolBeebeep.headerChat,
      ),
      isEmpty,
    );
    expect(
      c.conversationsMap[peer.id]!.every((m) => !c.canRetryMessage(m)),
      isTrue,
    );
    expect(c.pendingOfflineMessageIds[peer.id] ?? {}, isEmpty);
  });

  test(
    'selection and receipt do not read; exposure reads only exact source message',
    () {
      hello('192.0.2.1', bee: true);
      hello('192.0.2.1', port: 6477);
      final peer = c.peersMap['192.0.2.1:6475']!;
      c.selectPeer(peer);
      server.sent.clear();
      c.handleIncomingMessage('192.0.2.1:6475', '901', 'Bee', DateTime.now());
      c.handleIncomingMessage('192.0.2.1:6477', '901', 'JA', DateTime.now());
      final messages = c.conversationsMap[peer.id]!;
      expect(
        messages.every((m) => m.status == MessageStatus.delivered),
        isTrue,
      );
      expect(peer.unreadCount, 2);
      c.selectPeer(peer);
      expect(peer.unreadCount, 2);
      final before = server.sent.length;
      c.markMessagesAsRead(peer.id, {messages.first});
      expect(messages.first.status, MessageStatus.read);
      expect(messages.last.status, MessageStatus.delivered);
      expect(peer.unreadCount, 1);
      expect(server.sent.length, before + 1);
      expect(server.sent.last.endpoint, '192.0.2.1:6475');
      c.markMessagesAsRead(peer.id, {messages.first});
      expect(server.sent.length, before + 1);
    },
  );

  test(
    'read receipt is exact, unknown IDs do not read latest or older messages',
    () {
      hello('192.0.2.1');
      final peer = c.peersMap['192.0.2.1:6475']!;
      final messages = List.generate(
        3,
        (i) => MessageModel(
          id: '${100 + i}',
          senderId: 'me',
          senderName: 'Me',
          recipientId: peer.id,
          text: 'sent $i',
          isMine: true,
          status: MessageStatus.delivered,
        ),
      );
      c.conversationsMap[peer.id] = messages;
      server.onRead!('192.0.2.1:6475', '101');
      expect(messages.map((m) => m.status), [
        MessageStatus.delivered,
        MessageStatus.read,
        MessageStatus.delivered,
      ]);
      server.onRead!('192.0.2.1:6475', 'unknown');
      expect(messages.last.status, MessageStatus.delivered);
    },
  );

  test(
    'received attachment read uses transfer ID and originating session only',
    () {
      hello('192.0.2.1');
      hello('192.0.2.1', port: 6477, bee: true);
      final peer = c.peersMap['192.0.2.1:6475']!;
      final incoming = MessageModel(
        id: 'file_192.0.2.1:6475/501',
        senderId: peer.id,
        senderName: 'Alice',
        recipientId: 'me',
        text: '',
        isMine: false,
        sourceSession: 'alice-ja',
        status: MessageStatus.sending,
        fileAttachment: const FileAttachmentInfo(
          fileName: 'photo.png',
          fileSize: 10,
        ),
      );
      c.conversationsMap[peer.id] = [incoming];
      final before = server.sent.length;
      c.markMessagesAsRead(peer.id, {incoming});
      expect(incoming.status, MessageStatus.sending);
      expect(server.sent.length, before);
      incoming.status = MessageStatus.delivered;
      c.markMessagesAsRead(peer.id, {incoming});
      expect(incoming.status, MessageStatus.read);
      expect(server.sent.last.endpoint, '192.0.2.1:6475');
      expect(server.sent.last.message['header'], ProtocolBeebeep.headerRead);
      expect(server.sent.last.message['text'], 'file_501');
      c.markMessagesAsRead(peer.id, {incoming});
      expect(server.sent.length, before + 1);
    },
  );

  test(
    'direct and group file receipts match each recipient and survive JSON',
    () {
      hello('192.0.2.1');
      hello('192.0.2.2', account: 'bob', host: 'PC-B');
      final alice = c.peersMap['192.0.2.1:6475']!;
      final bob = c.peersMap['192.0.2.2:6475']!;
      final direct = MessageModel(
        id: 'file_501',
        senderId: 'me',
        senderName: 'Me',
        recipientId: alice.id,
        text: '',
        isMine: true,
        status: MessageStatus.delivered,
        fileAttachment: const FileAttachmentInfo(
          fileName: 'one.txt',
          fileSize: 1,
        ),
      );
      c.conversationsMap[alice.id] = [direct];
      server.onRead!(bob.id, 'file_501');
      expect(direct.status, MessageStatus.delivered);
      server.onRead!(alice.id, 'file_501');
      expect(direct.status, MessageStatus.read);
      final group = MessageModel(
        id: 'file_multi_600',
        senderId: 'me',
        senderName: 'Me',
        recipientId: 'group_files',
        text: '',
        isMine: true,
        status: MessageStatus.delivered,
        fileAttachment: const FileAttachmentInfo(
          fileName: 'two.txt',
          fileSize: 2,
        ),
        attachmentTransfers: {alice.id: '601', bob.id: '602'},
        attachmentRecipientStatuses: {
          alice.id: MessageStatus.delivered,
          bob.id: MessageStatus.delivered,
        },
      );
      c.conversationsMap['group_files'] = [group];
      server.onRead!(bob.id, 'file_601');
      expect(
        group.attachmentRecipientStatuses[alice.id],
        MessageStatus.delivered,
      );
      server.onRead!(alice.id, 'file_601');
      expect(group.status, MessageStatus.delivered);
      server.onRead!(bob.id, 'file_602');
      expect(group.status, MessageStatus.read);
      final restored = MessageModel.fromJson(group.toJson());
      restored.updateAttachmentRecipient(alice.id, MessageStatus.delivered);
      expect(restored.status, MessageStatus.read);
      expect(restored.attachmentTransfers, group.attachmentTransfers);
    },
  );

  test(
    'traffic cannot override advertised offline or revive a closed session',
    () {
      hello('192.0.2.1');
      final peer = c.peersMap['192.0.2.1:6475']!;
      c.handlePeerStatus(peer.id, {'data': '0', 'text': ''});
      expect(peer.status, PeerStatus.offline);
      for (var i = 0; i < 3; i++) {
        server.onActivity!(peer.id);
        expect(peer.status, PeerStatus.offline);
      }
      c.handlePeerStatus(peer.id, {'data': '3', 'text': 'away'});
      server.onActivity!(peer.id);
      expect(peer.status, PeerStatus.away);
      c.handlePeerStatus(peer.id, {'data': 'invalid', 'text': ''});
      expect(peer.status, PeerStatus.away);
      c.handlePeerDisconnected(peer.id);
      server.onActivity!(peer.id);
      c.handlePeerStatus(peer.id, {'data': '1', 'text': ''});
      expect(peer.status, PeerStatus.offline);
    },
  );

  test('secondary session activity does not replace preferred JA presence', () {
    hello('192.0.2.1');
    hello('192.0.2.1', port: 6477, bee: true);
    final peer = c.peersMap['192.0.2.1:6475']!;
    c.handlePeerStatus('192.0.2.1:6475', {'data': '2', 'text': 'busy'});
    c.handlePeerStatus('192.0.2.1:6477', {'data': '0', 'text': ''});
    server.onActivity!('192.0.2.1:6477');
    expect(peer.status, PeerStatus.busy);
  });

  test(
    'offline Buzz must not mark old owner online after reused-IP HELLO',
    () async {
      final reconnect = _ReconnectServer();
      server = reconnect;
      await restart();
      hello('192.0.2.1');
      final alice = c.peersMap['192.0.2.1:6475']!;
      c.selectPeer(alice);
      c.handlePeerDisconnected('192.0.2.1:6475');
      expect(alice.status, PeerStatus.offline);
      reconnect.connected = () =>
          hello('192.0.2.1', account: 'bob', host: 'PC-B');
      await c.sendBuzz();
      expect(alice.status, PeerStatus.offline);
      expect(
        reconnect.sent.where(
          (p) => p.message['header'] == ProtocolBeebeep.headerBuzz,
        ),
        isEmpty,
      );
      expect(
        c.conversationsMap[alice.id]?.where((m) => m.id.startsWith('buzz-')) ??
            [],
        isEmpty,
      );
    },
  );

  test(
    'group routing and permissions stay bound to the recorded session hash',
    () async {
      hello('192.0.2.1', bee: true);
      final peer = c.peersMap['192.0.2.1:6475']!;
      await c.createGroup('Pinned', [peer.id]);
      final group = c.groups.single;
      expect(group.memberRecords[peer.id]![2], 'alice-bee');
      hello('192.0.2.1', port: 6477);
      await c.sendMessage('group pinned');
      expect(server.sent.last.endpoint, '192.0.2.1:6475');
      group.adminIds.add('alice-bee');
      final remove = decode(
        ProtocolBeebeep.buildGroupPacket(
          groupId: group.id,
          name: group.name,
          updatedAt: group.updatedAt.add(const Duration(seconds: 1)),
          members: [],
          removed: true,
        ),
      );
      c.handleGroupPacket('192.0.2.1:6477', remove);
      expect(c.groups, hasLength(1));
      c.handleGroupPacket('192.0.2.1:6475', remove);
      expect(c.groups, isEmpty);
    },
  );

  test(
    'reused endpoint cannot inherit another identity history or outbox even after restart',
    () async {
      hello('192.0.2.1');
      final alice = c.peersMap['192.0.2.1:6475']!;
      c.selectPeer(alice);
      c.handlePeerDisconnected('192.0.2.1:6475');
      await c.sendMessage('private Alice');
      await restart();
      c.selectPeer(c.peersMap[alice.id]);
      hello('192.0.2.1', account: 'bob', host: 'PC-B');
      final bob = c.peers.firstWhere((p) => p.name == 'bob');
      expect(bob.id, isNot(alice.id));
      expect(c.currentMessages.single.text, 'private Alice');
      server.sent.clear();
      await c.flushPendingOutgoingMessagesForPeer(bob);
      expect(
        server.sent.where((p) => p.message['text'] == 'private Alice'),
        isEmpty,
      );
      c.handleIncomingMessage(
        '192.0.2.1:6475',
        'bob-1',
        'Bob says hi',
        DateTime.now(),
      );
      c.selectPeer(bob);
      expect(c.currentMessages.single.text, 'Bob says hi');
      await restart();
      expect(c.peers.where((p) => !p.isAiAssistant), hasLength(2));
    },
  );

  test(
    'same incoming message ID from two applications survives, retransmission deduplicates',
    () {
      hello('192.0.2.1', bee: true);
      hello('192.0.2.1', port: 6477);
      c.selectPeer(c.peersMap['192.0.2.1:6475']);
      final time = DateTime.now();
      c.handleIncomingMessage('192.0.2.1:6475', '10', 'Bee', time);
      c.handleIncomingMessage('192.0.2.1:6477', '10', 'JA', time);
      c.handleIncomingMessage('192.0.2.1:6477', '10', 'JA', time);
      expect(c.currentMessages.map((m) => m.text), ['Bee', 'JA']);
    },
  );

  test(
    'three persisted aliases retain both directions and canonicalize pending targets',
    () async {
      final ids = ['192.0.2.1:6475', '192.0.2.2:6475', '192.0.2.3:6477'];
      for (var i = 0; i < ids.length; i++) {
        devices.recordDevice(
          identityKey: 'alice@pc-a',
          username: 'alice',
          ip: ids[i].split(':').first,
        );
        await c.chatHistory.saveImmediately(ids[i], [
          MessageModel(
            id: '100',
            senderId: i == 0 ? 'me' : ids[i],
            senderName: 'alice',
            recipientId: i == 0 ? ids[i] : 'me',
            text: 'message-$i',
            isMine: i == 0,
            sourceSession: i == 0 ? null : 'session-$i',
            status: i == 0 ? MessageStatus.failed : MessageStatus.delivered,
            pendingRecipients: i == 0 ? {ids[i]} : null,
          ),
        ]);
      }
      await restart();
      final peer = c.peers.where((p) => !p.isAiAssistant).single;
      c.selectPeer(peer);
      expect(c.currentMessages, hasLength(3));
      hello('192.0.2.3', port: 6477);
      await c.flushPendingOutgoingMessagesForPeer(peer);
      expect(
        server.sent.where((p) => p.message['text'] == 'message-0'),
        hasLength(1),
      );
      await restart();
      c.selectPeer(c.peers.where((p) => !p.isAiAssistant).single);
      expect(c.currentMessages, hasLength(3));
      expect(
        c.currentMessages.where((m) => m.isMine).single.pendingRecipients,
        isEmpty,
      );
      c.clearConversation(c.selectedPeer!.id);
      await restart();
      expect(c.conversationsMap.values.expand((m) => m), isEmpty);
    },
  );
}
