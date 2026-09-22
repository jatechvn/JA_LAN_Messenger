import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/file_transfer_task.dart';
import 'package:ja_lan_messenger/modules/models/group_model.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/peer_list_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File prefFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('group_lifecycle_test_');
    prefFile = File('${tempDir.path}/prefs.json');
    AppPreferences().setCustomFileForTesting(prefFile);
    await AppPreferences().load();
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${tempDir.path}/groups.json',
    );
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('GroupModel and PeerModel Group Metadata Tests', () {
    test(
      'GroupModel stores and serializes unreadCount, lastMessage, and lastMessageTime',
      () {
        final now = DateTime.now();
        final group = GroupModel(
          id: 'group_123',
          name: 'Project Team',
          memberIds: ['user1', 'user2'],
          unreadCount: 3,
          lastMessage: 'Hello team',
          lastMessageTime: now,
        );

        expect(group.unreadCount, equals(3));
        expect(group.lastMessage, equals('Hello team'));
        expect(group.lastMessageTime, equals(now));

        final json = group.toJson();
        expect(json['unreadCount'], equals(3));
        expect(json['lastMessage'], equals('Hello team'));
        expect(json['lastMessageTime'], equals(now.toIso8601String()));

        final restored = GroupModel.fromJson(json);
        expect(restored.unreadCount, equals(3));
        expect(restored.lastMessage, equals('Hello team'));
        expect(
          restored.lastMessageTime?.millisecondsSinceEpoch,
          equals(now.millisecondsSinceEpoch),
        );

        final copied = group.copyWith(
          unreadCount: 0,
          lastMessage: 'Updated text',
        );
        expect(copied.unreadCount, equals(0));
        expect(copied.lastMessage, equals('Updated text'));
        expect(copied.id, equals('group_123'));
      },
    );

    test(
      'PeerModel.fromGroup correctly copies group unreadCount, lastMessage, and lastMessageTime',
      () {
        final now = DateTime.now();
        final group = GroupModel(
          id: 'group_456',
          name: 'DevOps Chat',
          memberIds: ['dev1', 'dev2'],
          unreadCount: 5,
          lastMessage: 'Build succeeded',
          lastMessageTime: now,
        );

        final peer = PeerModel.fromGroup(group);
        expect(peer.isGroup, isTrue);
        expect(peer.id, equals('group_456'));
        expect(peer.name, equals('DevOps Chat'));
        expect(peer.unreadCount, equals(5));
        expect(peer.lastMessage, equals('Build succeeded'));
        expect(peer.lastMessageTime, equals(now));
      },
    );
  });

  group('ProtocolBeebeep Typing Packet with GroupId Tests', () {
    test(
      'buildTypingPacket sets data to empty string when groupId is null',
      () {
        final packetBytes = ProtocolBeebeep.buildTypingPacket(isTyping: true);
        final rawStr = utf8.decode(packetBytes);
        final parsed = ProtocolBeebeep.parseMessage(rawStr);

        expect(parsed, isNotNull);
        expect(parsed!['header'], equals(ProtocolBeebeep.headerUser));
        expect(parsed['data'], equals(''));
      },
    );

    test('buildTypingPacket sets data to groupId when provided', () {
      final packetBytes = ProtocolBeebeep.buildTypingPacket(
        isTyping: true,
        groupId: 'group_alpha',
      );
      final rawStr = utf8.decode(packetBytes);
      final parsed = ProtocolBeebeep.parseMessage(rawStr);

      expect(parsed, isNotNull);
      expect(parsed!['header'], equals(ProtocolBeebeep.headerUser));
      expect(parsed['data'], equals('group_alpha'));
    });
  });

  group('Group Typing Formatting and Status Tests', () {
    test(
      'isGroupTyping and getGroupTypingText format members typing properly',
      () {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        coordinator.createGroup('Testing Group', [
          'peer_1',
          'peer_2',
          'peer_3',
        ]);
        final group = coordinator.groups.first;
        final lang = LanguageProvider();

        expect(coordinator.isGroupTyping(group.id), isFalse);
        expect(coordinator.getGroupTypingText(group.id, lang), isNull);

        // Simulate peer_1 typing in group
        coordinator.simulateGroupTypingForTesting(
          group.id,
          'peer_1',
          'Alice',
          true,
        );
        expect(coordinator.isGroupTyping(group.id), isTrue);
        expect(
          coordinator.getGroupTypingText(group.id, lang),
          contains('Alice'),
        );
        expect(
          coordinator.getGroupTypingText(group.id, lang),
          contains(lang.tr('typing')),
        );

        // Simulate peer_2 also typing
        coordinator.simulateGroupTypingForTesting(
          group.id,
          'peer_2',
          'Bob',
          true,
        );
        final textTwo = coordinator.getGroupTypingText(group.id, lang);
        expect(textTwo, contains('Alice'));
        expect(textTwo, contains('Bob'));
        expect(textTwo, contains(lang.tr('typing')));

        // Simulate peer_3 also typing (3+ members -> count + peopleTyping)
        coordinator.simulateGroupTypingForTesting(
          group.id,
          'peer_3',
          'Charlie',
          true,
        );
        final textThree = coordinator.getGroupTypingText(group.id, lang);
        expect(textThree, contains('3'));
        expect(textThree, contains(lang.tr('peopleTyping')));

        // Stop peer_3
        coordinator.simulateGroupTypingForTesting(
          group.id,
          'peer_3',
          'Charlie',
          false,
        );

        // Simulate peer_1 stopped typing
        coordinator.simulateGroupTypingForTesting(
          group.id,
          'peer_1',
          'Alice',
          false,
        );
        final textOne = coordinator.getGroupTypingText(group.id, lang);
        expect(textOne, contains('Bob'));

        // Simulate Bob stopped typing
        coordinator.simulateGroupTypingForTesting(
          group.id,
          'peer_2',
          'Bob',
          false,
        );
        expect(coordinator.isGroupTyping(group.id), isFalse);
      },
    );
  });

  group('MessengerCoordinator Unread Count and Disbanding Tests', () {
    test('totalUnreadCount sums peers, allUsers, and groups unread counts', () {
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      coordinator.createGroup('Finance', ['peer_a']);
      final group = coordinator.groups.first;
      group.unreadCount = 4;

      coordinator.allUsersPeer.unreadCount = 2;

      expect(coordinator.totalUnreadCount, greaterThanOrEqualTo(6));

      // markAllAsRead resets all unread counts
      coordinator.markAllAsRead();
      expect(group.unreadCount, equals(0));
      expect(coordinator.allUsersPeer.unreadCount, equals(0));
    });

    test(
      'deleteGroup removes group from coordinator and resets selectedPeer if active',
      () {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        coordinator.createGroup('Secret Squad', ['peer_x']);
        final group = coordinator.groups.first;
        final peer = PeerModel.fromGroup(group);
        coordinator.selectPeer(peer);

        expect(coordinator.selectedPeer?.id, equals(group.id));

        coordinator.deleteGroup(group.id, notifyPeers: false);
        expect(coordinator.groups.any((g) => g.id == group.id), isFalse);
        expect(
          coordinator.selectedPeer?.id,
          equals(coordinator.allUsersPeer.id),
        );
      },
    );

    test(
      'PeerModel.generateColor returns a deterministic color from palette',
      () {
        final colorA = PeerModel.generateColor('user_123');
        final colorB = PeerModel.generateColor('user_123');
        final colorC = PeerModel.generateColor('user_999');

        expect(colorA, equals(colorB));
        expect(colorA.a, equals(1.0));
        expect(colorC.a, equals(1.0));
      },
    );
  });

  group('Group departure packets', () {
    late _RecordingServer server;
    late MessengerCoordinator coordinator;

    void rememberPeer(String ip, String name) {
      coordinator.handlePeerHandshake(ip, {
        'port': 6475,
        'username': name,
        'account': name,
        'hostname': '$name-PC',
        'hash': '$name-hash',
      }, _UnusedSocket());
    }

    Map<String, dynamic> groupPacket(
      String id,
      DateTime time, {
      bool removed = false,
      bool left = false,
      bool kicked = false,
    }) => ProtocolBeebeep.parseMessage(
      utf8.decode(
        ProtocolBeebeep.buildGroupPacket(
          groupId: id,
          name: 'Team',
          updatedAt: time,
          members: const [],
          removed: removed,
          left: left,
          kicked: kicked,
        ),
      ),
    )!;

    setUp(() {
      server = _RecordingServer();
      coordinator = MessengerCoordinator(tcpServer: server);
      addTearDown(coordinator.dispose);
      rememberPeer('192.0.2.1', 'Alice');
    });

    test(
      'disband sends flag 512 and a later snapshot does not recreate it',
      () {
        coordinator.createGroup('Team', ['192.0.2.1:6475']);
        final group = coordinator.groups.single;
        server.sent.clear();

        coordinator.deleteGroup(group.id);

        expect(server.sent.single.flags, ProtocolBeebeep.flagGroupDisbanded);
        expect(coordinator.groups, isEmpty);

        coordinator.clearToast();
        server.sent.clear();
        coordinator.handleGroupPacket(
          '192.0.2.1:6475',
          groupPacket(group.id, DateTime.now()),
        );
        expect(coordinator.groups, isEmpty);
        expect(server.sent.single.flags, ProtocolBeebeep.flagGroupDisbanded);
        expect(coordinator.currentToast?.key, isNull);
      },
    );

    test('kick uses native flag 512 and says removed, not disbanded', () {
      final created = DateTime.now().subtract(const Duration(seconds: 2));
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        groupPacket('group_remote', created),
      );
      expect(coordinator.groups, isNotEmpty);
      server.sent.clear();

      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        groupPacket('group_remote', DateTime.now(), kicked: true),
      );

      expect(coordinator.groups, isEmpty);
      expect(coordinator.currentToast?.key, 'removedFromGroupToast');
      expect(coordinator.currentToast?.args, ['Team']);

      server.sent.clear();
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        groupPacket('group_remote', DateTime.now()),
      );
      expect(coordinator.groups, isEmpty);
      expect(server.sent.single.flags, ProtocolBeebeep.flagGroupLeft);
    });

    test(
      'leave sends native flag 32 and survives a stale roster plus restart',
      () {
        coordinator.createGroup('Team', ['192.0.2.1:6475']);
        final group = coordinator.groups.single;
        server.sent.clear();

        coordinator.leaveGroup(group.id);

        expect(server.sent.single.flags, ProtocolBeebeep.flagGroupLeft);
        expect(server.sent.single.endpoint, '192.0.2.1:6475');
        expect(coordinator.groups, isEmpty);

        server.sent.clear();
        coordinator.handleGroupPacket(
          '192.0.2.1:6475',
          groupPacket(group.id, DateTime.now()),
        );
        expect(coordinator.groups, isEmpty);
        expect(server.sent.single.flags, ProtocolBeebeep.flagGroupLeft);

        final restoredServer = _RecordingServer();
        final restored = MessengerCoordinator(tcpServer: restoredServer);
        addTearDown(restored.dispose);
        restored.handlePeerHandshake('192.0.2.1', {
          'port': 6475,
          'username': 'Alice',
          'account': 'Alice',
          'hostname': 'Alice-PC',
          'hash': 'Alice-hash',
        }, _UnusedSocket());
        restoredServer.sent.clear();
        restored.handleGroupPacket(
          '192.0.2.1:6475',
          groupPacket(group.id, DateTime.now()),
        );
        expect(restored.groups, isEmpty);
        expect(restoredServer.sent.single.flags, ProtocolBeebeep.flagGroupLeft);
      },
    );

    test('a member leaving removes only that member', () {
      coordinator.createGroup('Team', ['192.0.2.1:6475', '192.0.2.2:6475']);
      final group = coordinator.groups.single;
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        groupPacket(group.id, DateTime.now(), left: true),
      );
      expect(coordinator.groups.single.memberIds, ['192.0.2.2:6475']);
      expect(coordinator.currentToast?.key, isNot('groupDisbandedToast'));
    });

    test('incoming disband uses the disbanded toast', () {
      final created = DateTime.now().subtract(const Duration(seconds: 2));
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        groupPacket('group_remote', created),
      );
      expect(coordinator.groups, isNotEmpty);
      coordinator.clearToast();
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        groupPacket('group_remote', DateTime.now(), removed: true),
      );
      expect(coordinator.groups, isEmpty);
      expect(coordinator.currentToast?.key, 'groupDisbandedToast');
    });
  });

  test(
    'opening a group clears the unread badge and keeps the separator anchor',
    () {
      final coordinator = MessengerCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.createGroup('Team', ['192.0.2.1:6475']);
      final group = coordinator.groups.single;
      coordinator.conversationsMap[group.id] = [
        MessageModel(
          id: 'm1',
          senderId: '192.0.2.1:6475',
          senderName: 'Alice',
          recipientId: group.id,
          text: 'hello',
          isMine: false,
          status: MessageStatus.delivered,
        ),
      ];
      group.unreadCount = 2;
      coordinator.selectPeer(coordinator.allUsersPeer);
      coordinator.selectPeer(coordinator.getPeerForGroup(group));
      expect(coordinator.groups.single.unreadCount, 0);
      expect(coordinator.getInitialUnreadMessageId(group.id), 'm1');
      expect(
        coordinator.conversationsMap[group.id]!.single.status,
        MessageStatus.read,
      );
    },
  );

  test(
    'a group reply preview stores the new text without the quote block',
    () async {
      final coordinator = MessengerCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.createGroup('Team', ['192.0.2.1:6475']);
      await coordinator.sendMessage(
        'chào nhóm',
        replyTo: MessageModel(
          id: 'quoted',
          senderId: '192.0.2.1:6475',
          senderName: 'Alice',
          recipientId: coordinator.groups.single.id,
          text: 'câu cũ',
          isMine: false,
        ),
      );
      expect(coordinator.groups.single.lastMessage, 'chào nhóm');
    },
  );

  test('an incoming group file stays in the group conversation', () {
    final coordinator = MessengerCoordinator(tcpServer: _RecordingServer());
    addTearDown(coordinator.dispose);
    coordinator.handlePeerHandshake('192.0.2.1', {
      'port': 6475,
      'username': 'Alice',
      'account': 'Alice',
      'hostname': 'Alice-PC',
      'hash': 'alice-hash',
    }, _UnusedSocket());
    coordinator.createGroup('Team', ['192.0.2.1:6475']);
    final group = coordinator.groups.single;
    coordinator.selectPeer(coordinator.allUsersPeer);

    FileTransferTask incoming(String id, String? groupId) => FileTransferTask(
      id: id,
      fileName: 'note.txt',
      filePath: 'note.txt',
      fileSize: 4,
      isUpload: false,
      peerId: '192.0.2.1:6475',
      peerName: 'Alice',
      peerIp: '192.0.2.1',
      status: TransferStatus.completed,
      groupId: groupId,
    );

    coordinator.receiveFileForTesting(incoming('file-1', group.id));
    expect(
      coordinator.conversationsMap[group.id]!.single.text,
      contains('note.txt'),
    );
    expect(coordinator.conversationsMap.containsKey('192.0.2.1:6475'), isFalse);
    expect(group.unreadCount, 1);
    expect(group.lastMessage, contains('note.txt'));
    expect(group.lastMessage, isNot(startsWith('>')));

    coordinator.receiveFileForTesting(incoming('file-2', 'group_other'));
    expect(coordinator.conversationsMap[group.id]!.length, 1);
    expect(
      coordinator.conversationsMap['192.0.2.1:6475']!.single.id,
      'file_file-2',
    );
  });

  testWidgets('sidebar close asks before disbanding the group', (tester) async {
    final coordinator = MessengerCoordinator();
    final lang = LanguageProvider();
    final theme = ThemeProvider(initialMode: 'dark');
    addTearDown(coordinator.dispose);
    addTearDown(lang.dispose);
    addTearDown(theme.dispose);
    coordinator.createGroup('Team', const []);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MessengerCoordinator>.value(
            value: coordinator,
          ),
          ChangeNotifierProvider<LanguageProvider>.value(value: lang),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: const MaterialApp(home: Scaffold(body: PeerListView())),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text(lang.tr('disbandGroupConfirm')), findsOneWidget);
    expect(find.text(lang.tr('deleteGroup')), findsWidgets);
    expect(coordinator.groups, isNotEmpty);

    await tester.tap(find.text(lang.tr('cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(coordinator.groups, isNotEmpty);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text(lang.tr('confirm')));
    await tester.pump();
    expect(coordinator.groups, isEmpty);
  });
}

class _RecordingServer extends LanTcpServer {
  final sent = <({String endpoint, int flags})>[];

  @override
  bool send(String endpoint, List<int> packet) {
    final message = ProtocolBeebeep.parseMessage(utf8.decode(packet));
    sent.add((endpoint: endpoint, flags: message?['flags'] as int? ?? -1));
    return true;
  }
}

class _UnusedSocket implements Socket {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
