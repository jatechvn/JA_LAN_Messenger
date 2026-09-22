import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/models/group_model.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/avatar_picker_dialog.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/group_members_dialog.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/group_mention_picker.dart';

class RecordingServer extends LanTcpServer {
  final sent = <({String endpoint, Map<String, dynamic> message})>[];
  @override
  bool send(String endpoint, List<int> packet) {
    sent.add((endpoint: endpoint, message: decode(packet)));
    return true;
  }
}

class UnusedSocket implements Socket {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> decode(List<int> packet) =>
    ProtocolBeebeep.parseMessage(utf8.decode(packet))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late MessengerCoordinator coordinator;
  late RecordingServer server;
  late LanguageProvider lang;

  void peer(String ip, String name, String hash) {
    coordinator.handlePeerHandshake(ip, {
      'port': 6475,
      'username': name,
      'account': name,
      'hostname': '$name-PC',
      'hash': hash,
    }, UnusedSocket());
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ja_group_sync_');
    AppPreferences().setCustomFileForTesting(File('${dir.path}/prefs.json'));
    await AppPreferences().load();
    ChatHistoryService().setCustomDirectoryForTesting(
      Directory('${dir.path}/history')..createSync(),
    );
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${dir.path}/groups.json',
    );
    ThemeProvider.registryQueryOverride = (_, _) => null;
    server = RecordingServer();
    coordinator = MessengerCoordinator(
      tcpServer: server,
      knownDevices: KnownDevicesRegistry('${dir.path}/devices.json'),
    );
    coordinator.localUsername = 'Johnny';
    lang = LanguageProvider();
    peer('192.0.2.1', 'Alice', 'alice-hash');
    peer('192.0.2.2', 'Bảo Nguyễn', 'bao-hash');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  tearDown(() async {
    coordinator.dispose();
    lang.dispose();
    await ChatHistoryService().flush();
    ChatHistoryService().setCustomDirectoryForTesting(null);
    AppPreferences().setCustomFileForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
    ThemeProvider.registryQueryOverride = null;
    await dir.delete(recursive: true);
  });

  Map<String, dynamic> invite(
    String id,
    DateTime time, {
    List<List<String>> members = const [],
    bool removed = false,
  }) => decode(
    ProtocolBeebeep.buildGroupPacket(
      groupId: id,
      name: 'Team',
      updatedAt: time,
      members: members,
      removed: removed,
    ),
  );

  test(
    'create/add sync every recipient, count self, persist records, retry on reconnect',
    () {
      coordinator.createGroup('Team', [
        '192.0.2.1:6475',
        'me',
        '192.0.2.1:6475',
      ]);
      final group = coordinator.groups.single;
      expect(group.memberCount, 2);
      expect(coordinator.groupMembers(group.id).map((p) => p.name), [
        'Johnny',
        'Alice',
      ]);
      expect(server.sent.single.message['header'], ProtocolBeebeep.headerGroup);
      coordinator.addGroupMembers(group.id, ['192.0.2.2:6475']);
      final toAlice = server.sent.lastWhere(
        (p) => p.endpoint == '192.0.2.1:6475',
      );
      expect(ProtocolBeebeep.groupRecords(toAlice.message['text']), [
        ['Bảo Nguyễn', 'Bảo Nguyễn', 'bao-hash', ''],
      ]);
      expect(coordinator.groups.single.memberCount, 3);
      final restored = GroupModel.listFromJson(
        MessengerCoordinator.customGroupsFileForTesting!.readAsStringSync(),
      ).single;
      expect(restored.memberCount, 3);
      expect(restored.memberRecords['192.0.2.2:6475']![2], 'bao-hash');
      server.sent.clear();
      peer('192.0.2.2', 'Bảo Nguyễn', 'bao-hash');
      expect(server.sent.single.endpoint, '192.0.2.2:6475');
      expect(server.sent.single.message['header'], ProtocolBeebeep.headerGroup);
    },
  );

  test(
    'roster updates preserve local unread, preview and timestamp on disk',
    () {
      final time = DateTime.now().subtract(const Duration(seconds: 2));
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        invite('group_metadata', time),
      );
      final group = coordinator.groups.single;
      group.unreadCount = 7;
      group.lastMessage = 'Important preview';
      group.lastMessageTime = time;
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        invite(
          'group_metadata',
          DateTime.now(),
          members: [
            ['Bảo', 'bao', 'bao-hash', ''],
          ],
        ),
      );
      final updated = coordinator.groups.single;
      expect(updated.memberCount, 3);
      expect(updated.unreadCount, 7);
      expect(updated.lastMessage, 'Important preview');
      expect(updated.lastMessageTime, time);
      final disk = GroupModel.listFromJson(
        MessengerCoordinator.customGroupsFileForTesting!.readAsStringSync(),
      ).single;
      expect(disk.unreadCount, 7);
      expect(disk.lastMessage, 'Important preview');
    },
  );

  // Literal protocol fixtures, intentionally independent of our flag constants.
  Map<String, dynamic> nativeControl(
    String id,
    int flags,
  ) => ProtocolBeebeep.parseMessage(
    'BEE-GROU\u202999\u20290\u2029$flags\u2029\u2028$id\u2028Team\u2028\u20292026-09-22T00:00:00Z\u2029',
  )!;

  test('native Refused=32 with no group revision removes only sender', () {
    coordinator.createGroup('Team', ['192.0.2.1:6475', '192.0.2.2:6475']);
    final group = coordinator.groups.single;
    final before = group.updatedAt;
    coordinator.handleGroupPacket(
      '192.0.2.1:6475',
      nativeControl(group.id, 32),
    );
    expect(coordinator.groups.single.memberIds, ['192.0.2.2:6475']);
    expect(coordinator.groups.single.updatedAt.isBefore(before), isFalse);
  });

  test(
    'native Delete=512 removes recipient without global-disband semantics',
    () {
      coordinator.createGroup('Team', ['192.0.2.1:6475']);
      final id = coordinator.groups.single.id;
      coordinator.handleGroupPacket('192.0.2.1:6475', nativeControl(id, 512));
      expect(coordinator.groups, isEmpty);
      expect(coordinator.currentToast!.key, 'removedFromGroupToast');
      final departure = jsonDecode(
        File('${dir.path}/group_departures.json').readAsStringSync(),
      );
      expect(departure['left'], contains(id));
      expect(departure['disbanded'], isNot(contains(id)));
    },
  );

  test(
    'outbound flags match native semantics and only disband has extension',
    () {
      final time = DateTime.now();
      Map<String, dynamic> packet({
        bool left = false,
        bool kicked = false,
        bool disband = false,
      }) => decode(
        ProtocolBeebeep.buildGroupPacket(
          groupId: 'group_flags',
          name: 'Team',
          updatedAt: time,
          members: [],
          left: left,
          kicked: kicked,
          removed: disband,
        ),
      );
      expect(packet(left: true)['flags'], 32);
      expect(packet(kicked: true)['flags'], 512);
      expect(
        (packet(kicked: true)['data'] as String).split('\u2028').length,
        4,
      );
      final disband = packet(disband: true);
      expect(disband['flags'], 512);
      expect(
        (disband['data'] as String).split('\u2028').last,
        'ja-group-v1:disband',
      );
      coordinator.createGroup('Team', ['192.0.2.1:6475']);
      final id = coordinator.groups.single.id;
      coordinator.handleGroupPacket('192.0.2.1:6475', nativeControl(id, 1024));
      coordinator.handleGroupPacket('192.0.2.1:6475', nativeControl(id, 2048));
      expect(coordinator.groups, hasLength(1));
    },
  );

  Map<String, dynamic> reinvite(
    String id,
    DateTime invitation, {
    DateTime? revision,
  }) => decode(
    ProtocolBeebeep.buildGroupPacket(
      groupId: id,
      name: 'Team',
      updatedAt: revision ?? invitation,
      members: [],
      invitedAt: invitation,
    ),
  );

  test(
    'restart rejects old invite and plain snapshots but accepts a fresh invite from prior member',
    () {
      coordinator.createGroup('Team', ['192.0.2.1:6475']);
      final group = coordinator.groups.single;
      final oldTime = group.updatedAt;
      coordinator.leaveGroup(group.id);
      coordinator.dispose();
      coordinator = MessengerCoordinator(
        tcpServer: server,
        knownDevices: KnownDevicesRegistry('${dir.path}/devices.json'),
      );
      peer('192.0.2.1', 'Alice', 'alice-hash');
      peer('192.0.2.2', 'Bảo Nguyễn', 'bao-hash');
      final newTime = DateTime.now().add(const Duration(seconds: 1));
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        reinvite(group.id, oldTime, revision: newTime),
      );
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        invite(group.id, newTime),
      );
      // A different known peer was not in this departed group.
      coordinator.handleGroupPacket(
        '192.0.2.2:6475',
        reinvite(group.id, newTime),
      );
      expect(coordinator.groups, isEmpty);
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        reinvite(group.id, newTime),
      );
      expect(coordinator.groups.single.id, group.id);
      // Leaving again must reject replay of that invitation, even with a new roster revision.
      coordinator.leaveGroup(group.id);
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        reinvite(
          group.id,
          newTime,
          revision: newTime.add(const Duration(seconds: 1)),
        ),
      );
      expect(coordinator.groups, isEmpty);
    },
  );

  test('kick permits a fresh explicit invite; disband stays terminal', () {
    coordinator.createGroup('Team', ['192.0.2.1:6475']);
    final id = coordinator.groups.single.id;
    coordinator.handleGroupPacket('192.0.2.1:6475', nativeControl(id, 512));
    final fresh = DateTime.now().add(const Duration(seconds: 1));
    coordinator.handleGroupPacket('192.0.2.1:6475', reinvite(id, fresh));
    expect(coordinator.groups.single.id, id);
    coordinator.deleteGroup(id);
    coordinator.handleGroupPacket(
      '192.0.2.1:6475',
      reinvite(id, fresh.add(const Duration(seconds: 1))),
    );
    expect(coordinator.groups, isEmpty);
  });

  test(
    'invitation issuance is per new member and retries keep the same time',
    () {
      coordinator.createGroup('Team', ['192.0.2.1:6475']);
      final id = coordinator.groups.single.id;
      final original = ProtocolBeebeep.groupMetadata(
        server.sent.last.message,
      )!.invitedAt;
      coordinator.addGroupMembers(id, ['192.0.2.2:6475']);
      expect(
        ProtocolBeebeep.groupMetadata(
          server.sent.lastWhere((p) => p.endpoint == '192.0.2.1:6475').message,
        )!.invitedAt,
        original,
      );
      final baoInvite = coordinator.groups.single.invitations['192.0.2.2:6475'];
      expect(baoInvite, isNotNull);
      final disk = GroupModel.listFromJson(
        MessengerCoordinator.customGroupsFileForTesting!.readAsStringSync(),
      ).single;
      expect(
        disk.invitations['192.0.2.2:6475']!.isAtSameMomentAs(baoInvite!),
        isTrue,
      );
      server.sent.clear();
      peer('192.0.2.2', 'Bảo Nguyễn', 'bao-hash');
      expect(
        ProtocolBeebeep.groupMetadata(server.sent.single.message)!.invitedAt,
        baoInvite.toUtc(),
      );
    },
  );

  test(
    'recipient sees invited group; known and undiscovered members resolve by hash',
    () {
      final time = DateTime.now().subtract(const Duration(seconds: 2));
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        invite(
          'group_remote',
          time,
          members: [
            ['Bảo Nguyễn', 'bao', 'bao-hash', ''],
            ['Carol', 'carol', 'carol-hash', ''],
          ],
        ),
      );
      expect(coordinator.groups.single.memberCount, 4);
      expect(coordinator.groupMembers('group_remote').map((p) => p.name), [
        'Johnny',
        'Alice',
        'Bảo Nguyễn',
        'Carol',
      ]);
      peer('192.0.2.3', 'Carol', 'carol-hash');
      expect(coordinator.groups.single.memberIds, contains('192.0.2.3:6475'));
      expect(
        coordinator.groups.single.memberIds,
        isNot(contains('hash:carol-hash')),
      );
      expect(coordinator.groups.single.memberCount, 4);
      // A stale request or non-member cannot overwrite current membership.
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        invite('group_remote', time.subtract(const Duration(seconds: 1))),
      );
      peer('192.0.2.4', 'Outsider', 'outside-hash');
      coordinator.handleGroupPacket(
        '192.0.2.4:6475',
        invite('group_remote', DateTime.now()),
      );
      expect(coordinator.groups.single.memberCount, 4);
      coordinator.handleGroupPacket(
        '192.0.2.1:6475',
        invite('group_remote', DateTime.now(), removed: true),
      );
      expect(coordinator.groups, isEmpty);
    },
  );

  test(
    'group chats route by ID despite identical names and preserve mentions',
    () {
      final time = DateTime.now();
      for (final id in ['group_one', 'group_two']) {
        coordinator.handleGroupPacket('192.0.2.1:6475', invite(id, time));
      }
      final packet = decode(
        ProtocolBeebeep.buildChatPacket(
          messageId: '123',
          text: '@Johnny xin chào',
          groupId: 'group_two',
          groupName: 'Team',
          groupUpdatedAt: time,
        ),
      );
      coordinator.handleGroupMessage('192.0.2.1:6475', packet);
      coordinator.handleGroupMessage('192.0.2.1:6475', packet);
      coordinator.selectPeer(PeerModel.fromGroup(coordinator.groups.first));
      expect(coordinator.currentMessages, isEmpty);
      coordinator.selectPeer(PeerModel.fromGroup(coordinator.groups.last));
      expect(coordinator.currentMessages.single.text, '@Johnny xin chào');
    },
  );

  test(
    'malformed group metadata and truncated member records are rejected',
    () {
      expect(ProtocolBeebeep.groupRecords('2\u2028Alice'), isNull);
      expect(
        ProtocolBeebeep.groupRecords('1\u2029Alice\u2029account\u2029hash'),
        isNull,
      );
      expect(
        ProtocolBeebeep.groupMetadata(invite('../bad', DateTime.now())),
        isNull,
      );
      final broken = invite('group_bad', DateTime.now())..['text'] = '200000';
      coordinator.handleGroupPacket('192.0.2.1:6475', broken);
      expect(coordinator.groups, isEmpty);
    },
  );

  test('mention token honors caret, Unicode, emails and composing text', () {
    TextEditingValue value(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    expect(activeMention(value('Hi @Bảo'))?.query, 'Bảo');
    expect(activeMention(value('test@example.com')), isNull);
    expect(activeMention(value('@Alice\nhello')), isNull);
    expect(
      activeMention(
        value('@Bảo').copyWith(composing: const TextRange(start: 1, end: 4)),
      ),
      isNull,
    );
  });

  Widget host(Widget child, ThemeProvider theme) => MultiProvider(
    providers: [
      ChangeNotifierProvider<MessengerCoordinator>.value(value: coordinator),
      ChangeNotifierProvider<LanguageProvider>.value(value: lang),
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  for (final mode in ['light', 'dark']) {
    testWidgets('avatar and member dialog foreground follows $mode theme', (
      tester,
    ) async {
      final theme = ThemeProvider(initialMode: mode);
      addTearDown(theme.dispose);
      await tester.pumpWidget(host(const AvatarPickerDialog(), theme));
      final label = tester.widget<Text>(find.text(lang.tr('presetIcons')));
      expect(
        label.style!.color!.computeLuminance(),
        mode == 'light' ? lessThan(0.2) : greaterThan(0.8),
      );
      coordinator.createGroup('Team', ['192.0.2.1:6475']);
      await tester.pumpWidget(
        host(GroupMembersDialog(groupPeer: coordinator.selectedPeer!), theme),
      );
      expect(find.text('Team (2)'), findsOneWidget);
      expect(find.text('Johnny'), findsOneWidget);
      final member = tester.widget<Text>(find.text('Alice'));
      expect(
        member.style!.color!.computeLuminance(),
        mode == 'light' ? lessThan(0.2) : greaterThan(0.8),
      );
      expect(find.byIcon(Icons.remove_circle_outline_rounded), findsOneWidget);
      if (mode == 'light') {
        final search = tester.widget<TextField>(find.byType(TextField));
        final hintOnWhite = Color.alphaBlend(
          search.decoration!.hintStyle!.color!,
          Colors.white,
        );
        expect(
          1.05 / (hintOnWhite.computeLuminance() + 0.05),
          greaterThan(4.5),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    '@ picker inserts full Unicode name at caret without deleting suffix',
    (tester) async {
      final theme = ThemeProvider(initialMode: 'light');
      addTearDown(theme.dispose);
      coordinator.createGroup('Team', ['192.0.2.2:6475']);
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'Hi @Bảo please',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(GroupMentionPicker(controller: controller), theme),
      );
      await tester.tap(find.text('@Bảo Nguyễn'));
      await tester.pump();
      expect(controller.text, 'Hi @Bảo Nguyễn  please');
      expect(find.text('@Bảo Nguyễn'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'encrypted TCP dispatches native group invitation and group chat separately',
    () async {
      final a = LanTcpServer(), b = LanTcpServer();
      final invitation = Completer<Map<String, dynamic>>();
      final chat = Completer<Map<String, dynamic>>();
      List<int> hello(String key, int port, String name) =>
          ProtocolBeebeep.buildHelloPacket(
            localPort: port,
            username: name,
            status: PeerStatus.online,
            statusDescription: '',
            accountName: name,
            appVersion: 'test',
            avatarHexColor: '#123456',
            workgroup: '',
            publicKey: key,
          );
      a.helloBuilder = (key) => hello(key, a.port, 'A');
      b.helloBuilder = (key) => hello(key, b.port, 'B');
      b.onGroup = (_, m) => invitation.complete(m);
      b.onGroupMessage = (_, m) => chat.complete(m);
      b.onMessage = (_, _, _, _) =>
          fail('Group message leaked into direct chat');
      try {
        expect(await a.start(port: 0), isTrue);
        expect(await b.start(port: 0), isTrue);
        expect(await a.connect('127.0.0.1', b.port), isTrue);
        final time = DateTime.now();
        a.send(
          '127.0.0.1:${b.port}',
          ProtocolBeebeep.buildGroupPacket(
            groupId: 'group_tcp',
            name: 'Team',
            updatedAt: time,
            members: [
              ['Bảo', 'bao', 'hash', ''],
            ],
          ),
        );
        a.send(
          '127.0.0.1:${b.port}',
          ProtocolBeebeep.buildChatPacket(
            messageId: '456',
            text: '@Bảo hello',
            groupId: 'group_tcp',
            groupName: 'Team',
            groupUpdatedAt: time,
          ),
        );
        expect(
          ProtocolBeebeep.groupMetadata(
            await invitation.future.timeout(const Duration(seconds: 5)),
          )!.id,
          'group_tcp',
        );
        expect(
          (await chat.future.timeout(const Duration(seconds: 5)))['text'],
          '@Bảo hello',
        );
      } finally {
        await a.stop();
        await b.stop();
      }
    },
  );

  test(
    'handleGroupPacket updates group avatarPreset and color from avatarPayload',
    () {
      peer('192.168.1.10', 'Alice', 'alice_hash');
      final time = DateTime.now();

      final packetBytes = ProtocolBeebeep.buildGroupPacket(
        groupId: 'group_avatar_test',
        name: 'Design Crew',
        updatedAt: time,
        members: [
          ['Alice', 'alice', 'alice_hash', ''],
        ],
        avatarPayload: '#EC4899|preset:palette',
      );

      final message = decode(packetBytes);
      coordinator.handleGroupPacket('192.168.1.10:6475', message);

      final group = coordinator.groups.firstWhere(
        (g) => g.id == 'group_avatar_test',
      );
      expect(group.name, equals('Design Crew'));
      expect(group.color, equals(const Color(0xFFEC4899)));
      expect(group.avatarPreset, equals('palette'));

      final groupPeer = coordinator.getPeerForGroup(group);
      expect(groupPeer.avatarPreset, equals('palette'));
      expect(groupPeer.avatarColor, equals(const Color(0xFFEC4899)));
    },
  );
}
