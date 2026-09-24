import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/group_model.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'group_sync_and_ui_test.dart' show RecordingServer, UnusedSocket, decode;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late MessengerCoordinator coordinator;
  late RecordingServer server;
  const member = '192.0.2.1:6475';
  const other = '192.0.2.2:6475';
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ja_permissions_');
    AppPreferences().setCustomFileForTesting(File('${dir.path}/prefs.json'));
    await AppPreferences().load();
    ChatHistoryService().setCustomDirectoryForTesting(
      Directory('${dir.path}/history')..createSync(),
    );
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${dir.path}/groups.json',
    );
    server = RecordingServer();
    coordinator = MessengerCoordinator(
      tcpServer: server,
      knownDevices: KnownDevicesRegistry('${dir.path}/devices.json'),
    );
    for (final entry in {
      '192.0.2.1': 'member-hash',
      '192.0.2.2': 'other-hash',
    }.entries) {
      coordinator.handlePeerHandshake(entry.key, {
        'port': 6475,
        'username': entry.value,
        'account': entry.value,
        'hash': entry.value,
      }, UnusedSocket());
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await coordinator.createGroup('Review', [member, other]);
  });
  tearDown(() async {
    coordinator.dispose();
    await ChatHistoryService().flush();
    ChatHistoryService().setCustomDirectoryForTesting(null);
    AppPreferences().setCustomFileForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
    await dir.delete(recursive: true);
  });

  Map<String, dynamic> update({
    bool removed = false,
    bool kicked = false,
    bool left = false,
    String? creator,
    bool includeOther = true,
  }) {
    final group = coordinator.groups.single;
    return decode(
      ProtocolBeebeep.buildGroupPacket(
        groupId: group.id,
        name: group.name,
        updatedAt: group.updatedAt.add(const Duration(seconds: 1)),
        members: [
          if (includeOther) ['Other', 'other', 'other-hash', ''],
        ],
        removed: removed,
        kicked: kicked,
        left: left,
        creatorId: creator,
        avatarPayload: '#123456|preset:rocket',
      ),
    );
  }

  test('member cannot disband by copying owner ID into control metadata', () {
    final group = coordinator.groups.single;
    final packet = update(removed: true);
    packet['data'] =
        '${packet['data']}${ProtocolBeebeep.dataFieldSeparator}${ProtocolBeebeep.groupCreatorPrefix}${group.creatorId}';
    coordinator.handleGroupPacket(member, packet);
    expect(coordinator.groups.single.id, group.id);
    expect(File('${dir.path}/group_departures.json').existsSync(), isFalse);
  });

  test('regular member snapshot cannot change ownership or avatar', () {
    final owner = coordinator.groups.single.creatorId;
    coordinator.handleGroupPacket(member, update(creator: 'member-hash'));
    final group = coordinator.groups.single;
    expect(group.creatorId, owner);
    expect(group.isAdmin('member-hash'), isFalse);
    expect(group.avatarPreset, isNull);
    final disk = GroupModel.listFromJson(
      MessengerCoordinator.customGroupsFileForTesting!.readAsStringSync(),
    ).single;
    expect(disk.creatorId, owner);
    coordinator.handleGroupPacket(member, update(removed: true));
    expect(coordinator.groups, hasLength(1));
  });

  test(
    'member cannot kick owner or remove another member through snapshot',
    () {
      coordinator.handleGroupPacket(member, update(kicked: true));
      expect(coordinator.groups, hasLength(1));
      coordinator.handleGroupPacket(member, update(includeOther: false));
      expect(coordinator.groups.single.memberIds, [member, other]);
    },
  );

  test('regular member may leave without admin privileges', () {
    coordinator.handleGroupPacket(member, update(left: true));
    expect(coordinator.groups.single.memberIds, [other]);
    expect(coordinator.isGroupAdmin(coordinator.groups.single.id), isTrue);
  });

  test(
    'local member cannot remove peers; owner can remove ordinary member',
    () {
      final group = coordinator.groups.single;
      coordinator.removeGroupMember(group.id, other);
      expect(coordinator.groups.single.memberIds, [member]);
      final remote = coordinator.groups.single;
      remote.creatorId = 'member-hash';
      remote.adminIds.clear();
      final sent = server.sent.length;
      coordinator.removeGroupMember(group.id, member);
      expect(coordinator.groups.single.memberIds, [member]);
      expect(server.sent.length, sent);
    },
  );

  test('authorized remote owner can kick a member', () {
    final group = coordinator.groups.single;
    group.creatorId = 'member-hash';
    group.adminIds.clear();
    coordinator.handleGroupPacket(member, update(kicked: true));
    expect(coordinator.groups, isEmpty);
  });

  test('authorized co-admin may disband but cannot kick owner', () {
    coordinator.groups.single.adminIds.add('member-hash');
    coordinator.handleGroupPacket(member, update(kicked: true));
    expect(coordinator.groups, hasLength(1));
    coordinator.handleGroupPacket(member, update(removed: true));
    expect(coordinator.groups, isEmpty);
  });

  test('co-admin cannot erase creator via a roster snapshot', () {
    final group = coordinator.groups.single;
    group.creatorId = 'other-hash';
    group.adminIds.add('member-hash');
    coordinator.handleGroupPacket(member, update(includeOther: false));
    expect(coordinator.groups.single.memberIds, contains(other));
  });

  test('pending avatar conversion cannot undo role revocation', () async {
    final group = coordinator.groups.single;
    final saving = coordinator.updateGroupAvatar(
      group.id,
      customPath: '${dir.path}/missing.png',
    );
    coordinator.transferGroupCreator(group.id, member);
    coordinator.groups.single.adminIds.clear();
    await saving;
    expect(coordinator.groups.single.creatorId, 'member-hash');
    expect(coordinator.isGroupAdmin(group.id), isFalse);
    expect(coordinator.groups.single.customAvatarPath, isNull);
  });

  test(
    'new invitations fit v1.3.0 six-field limit with avatar and invite intact',
    () {
      final message = server.sent.first.message;
      final fields = (message['data'] as String).split(
        ProtocolBeebeep.dataFieldSeparator,
      );
      expect(fields, hasLength(6));
      // The released parser recognizes these two extensions independently.
      expect(fields[4], startsWith(ProtocolBeebeep.groupInvitePrefix));
      expect(
        DateTime.tryParse(
          fields[4].substring(ProtocolBeebeep.groupInvitePrefix.length),
        ),
        isNotNull,
      );
      expect(fields[5], startsWith(ProtocolBeebeep.groupAvatarPrefix));
      final metadata = ProtocolBeebeep.groupMetadata(message)!;
      expect(metadata.creatorId, coordinator.groups.single.creatorId);
      expect(metadata.avatarPayload, isNot(contains('creator:')));
      expect(metadata.invitedAt, isNotNull);
    },
  );

  test('owner fallback rejects empty, short and malformed identities', () {
    final group = GroupModel(
      id: 'group_abcdef123456_123',
      name: 'Legacy',
      memberIds: [],
    );
    expect(group.isCreator(''), isFalse);
    expect(group.isCreator('abc'), isFalse);
    expect(group.isCreator('abcdef1234567890'), isTrue);
    group.creatorId = 'explicit-owner';
    expect(group.isCreator('abcdef1234567890'), isFalse);
    expect(group.isCreator('explicit-owner'), isTrue);
  });

  test('regular member cannot add peers through a snapshot', () {
    final group = coordinator.groups.single;
    final before = group.updatedAt;
    coordinator.handleGroupPacket(
      member,
      decode(
        ProtocolBeebeep.buildGroupPacket(
          groupId: group.id,
          name: group.name,
          updatedAt: before.add(const Duration(seconds: 1)),
          members: [
            ['Other', 'other', 'other-hash', ''],
            ['New', 'new', 'new-hash', ''],
          ],
        ),
      ),
    );
    expect(coordinator.groups.single.memberIds, [member, other]);
    expect(coordinator.groups.single.updatedAt, before);
  });

  test('admin grants use stable hashes and empty revocations survive wire', () {
    final group = coordinator.groups.single;
    group.adminIds.clear();
    coordinator.setGroupAdmin(group.id, member, admin: true);
    expect(coordinator.groups.single.adminIds, ['member-hash']);
    expect(ProtocolBeebeep.groupMetadata(server.sent.last.message)!.adminIds, [
      'member-hash',
    ]);
    coordinator.setGroupAdmin(group.id, member, admin: false);
    expect(
      ProtocolBeebeep.groupMetadata(server.sent.last.message)!.adminIds,
      isEmpty,
    );
  });

  test('remote role notices are localized, deduplicated and apply to self', () {
    final language = LanguageProvider()..setLanguage(AppLanguage.en);
    addTearDown(language.dispose);
    coordinator.languageProvider = language;
    final group = coordinator.groups.single;
    final localHash = group.creatorId!;
    group.creatorId = 'member-hash';
    group.adminIds.clear();
    Map<String, dynamic> roles(
      int revision,
      List<String> admins, {
      String? owner,
    }) => decode(
      ProtocolBeebeep.buildGroupPacket(
        groupId: group.id,
        name: group.name,
        updatedAt: group.updatedAt.add(Duration(seconds: revision)),
        members: [
          ['Other', 'other', 'other-hash', ''],
        ],
        creatorId: owner ?? 'member-hash',
        adminIds: admins,
        avatarPayload: '#123456',
      ),
    );
    final promote = roles(1, [localHash]);
    coordinator.handleGroupPacket(member, promote);
    coordinator.handleGroupPacket(member, promote);
    expect(coordinator.isGroupAdmin(group.id), isTrue);
    expect(coordinator.conversationsMap[group.id], hasLength(1));
    expect(
      coordinator.conversationsMap[group.id]!.single.text,
      contains(coordinator.localUsername),
    );
    coordinator.handleGroupPacket(member, roles(2, []));
    expect(coordinator.isGroupAdmin(group.id), isFalse);
    expect(coordinator.conversationsMap[group.id], hasLength(2));
    coordinator.handleGroupPacket(
      member,
      roles(3, ['member-hash'], owner: localHash),
    );
    expect(coordinator.isGroupCreator(group.id), isTrue);
    expect(coordinator.conversationsMap[group.id], hasLength(3));
    expect(
      coordinator.conversationsMap[group.id]!.last.text,
      contains('transferred ownership'),
    );
  });

  test(
    'ownership transfer retains old owner as admin even without stored admin entry',
    () {
      final group = coordinator.groups.single;
      final owner = group.creatorId!;
      group.adminIds.clear();
      coordinator.transferGroupCreator(group.id, member);
      expect(coordinator.isGroupAdmin(group.id), isTrue);
      expect(coordinator.groups.single.adminIds, contains(owner));
      expect(coordinator.groups.single.creatorId, 'member-hash');
    },
  );

  test(
    'new invitation remains history-free; later unknown member uses record name',
    () {
      coordinator.deleteGroup(coordinator.groups.single.id, notifyPeers: false);
      final time = DateTime.now();
      Map<String, dynamic> snapshot(int revision, List<List<String>> members) =>
          decode(
            ProtocolBeebeep.buildGroupPacket(
              groupId: 'group_remote',
              name: 'Remote',
              updatedAt: time.add(Duration(seconds: revision)),
              members: members,
              creatorId: 'member-hash',
              avatarPayload: '#123456|preset:rocket',
            ),
          );
      coordinator.handleGroupPacket(member, snapshot(0, []));
      expect(coordinator.conversationsMap['group_remote'] ?? [], isEmpty);
      expect(coordinator.groups.single.avatarPreset, 'rocket');
      coordinator.handleGroupPacket(
        member,
        snapshot(1, [
          ['Charlie', 'charlie', 'unknown-hash', ''],
        ]),
      );
      expect(
        coordinator.conversationsMap['group_remote']!.single.text,
        contains('Charlie'),
      );
    },
  );
}
