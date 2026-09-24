import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/group_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/app_avatar.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/avatar_picker_dialog.dart';
import 'package:ja_lan_messenger/modules/utils/avatar_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File prefFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avatar_test_');
    prefFile = File('${tempDir.path}/prefs.json');
    AppPreferences().setCustomFileForTesting(prefFile);
    await AppPreferences().load();
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('AvatarPresets Unit Tests', () {
    test('AvatarPresets has 16 preset icons and 12 palette colors', () {
      expect(AvatarPresets.icons.length, equals(16));
      expect(AvatarPresets.paletteColors.length, equals(12));

      expect(AvatarPresets.icons.containsKey('robot'), isTrue);
      expect(AvatarPresets.icons.containsKey('rocket'), isTrue);
      expect(AvatarPresets.icons.containsKey('cat'), isTrue);
      expect(AvatarPresets.icons.containsKey('game'), isTrue);
      expect(AvatarPresets.icons.containsKey('code'), isTrue);
    });

    test('AvatarPresets.getIcon returns expected IconData with fallback', () {
      expect(AvatarPresets.getIcon('robot'), equals(Icons.smart_toy_rounded));
      expect(AvatarPresets.getIcon('cat'), equals(Icons.pets_rounded));
      expect(AvatarPresets.getIcon('code'), equals(Icons.terminal_rounded));
      expect(AvatarPresets.getIcon(null), equals(Icons.person_rounded));
      expect(
        AvatarPresets.getIcon('non_existent_preset'),
        equals(Icons.person_rounded),
      );
    });
  });

  group('PeerModel Avatar Parsing Unit Tests', () {
    test('updateAvatarFromRaw parses color only', () {
      final peer = PeerModel(
        id: '127.0.0.1:49723',
        name: 'TestPeer',
        ip: '127.0.0.1',
        port: 49723,
      );

      peer.updateAvatarFromRaw('#10B981');
      expect(peer.avatarColor, equals(const Color(0xFF10B981)));
      expect(peer.avatarPreset, isNull);
      expect(peer.customAvatarPath, isNull);
      expect(peer.customAvatarBase64, isNull);
    });

    test('updateAvatarFromRaw parses color and preset', () {
      final peer = PeerModel(
        id: '127.0.0.1:49723',
        name: 'TestPeer',
        ip: '127.0.0.1',
        port: 49723,
      );

      peer.updateAvatarFromRaw('#EF4444|preset:rocket');
      expect(peer.avatarColor, equals(const Color(0xFFEF4444)));
      expect(peer.avatarPreset, equals('rocket'));
    });

    test('updateAvatarFromRaw parses color, base64 and custom path', () {
      final peer = PeerModel(
        id: '127.0.0.1:49723',
        name: 'TestPeer',
        ip: '127.0.0.1',
        port: 49723,
      );

      peer.updateAvatarFromRaw('#8B5CF6|b64:aGVsbG8=|path:C:/avatar.png');
      expect(peer.avatarColor, equals(const Color(0xFF8B5CF6)));
      expect(peer.customAvatarBase64, equals('aGVsbG8='));
      expect(peer.customAvatarPath, equals('C:/avatar.png'));
    });

    test(
      'updateAvatarFromRaw handles empty and malformed inputs gracefully',
      () {
        final peer = PeerModel(
          id: '127.0.0.1:49723',
          name: 'TestPeer',
          ip: '127.0.0.1',
          port: 49723,
          avatarColor: const Color(0xFF123456),
        );

        peer.updateAvatarFromRaw('');
        expect(peer.avatarColor, equals(const Color(0xFF123456)));

        peer.updateAvatarFromRaw('invalid_hex_format');
        expect(peer.avatarColor, equals(const Color(0xFF123456)));
      },
    );

    test(
      'updateAvatarFromRaw clears stale avatar metadata on initials payload',
      () {
        final peer = PeerModel(
          id: '127.0.0.1:49723',
          name: 'TestPeer',
          ip: '127.0.0.1',
          port: 49723,
          avatarPreset: 'rocket',
          customAvatarBase64: 'aGVsbG8=',
          customAvatarPath: 'C:/avatar.png',
        );

        peer.updateAvatarFromRaw('#123456|preset:initials');

        expect(peer.avatarPreset, equals('initials'));
        expect(peer.customAvatarBase64, isNull);
        expect(peer.customAvatarPath, isNull);

        peer.updateAvatarFromRaw('#654321');
        expect(peer.avatarPreset, isNull);
        expect(peer.customAvatarBase64, isNull);
        expect(peer.customAvatarPath, isNull);

        peer.avatarPreset = 'rocket';
        peer.updateAvatarFromRaw('not-a-color');
        expect(peer.avatarPreset, equals('rocket'));
      },
    );

    test('PeerModel.copyWith preserves avatar metadata', () {
      final peer = PeerModel(
        id: '127.0.0.1:49723',
        name: 'TestPeer',
        ip: '127.0.0.1',
        avatarPreset: 'rocket',
        customAvatarBase64: 'aGVsbG8=',
        customAvatarPath: 'C:/avatar.png',
      );

      final copied = peer.copyWith(name: 'Renamed');

      expect(copied.avatarPreset, equals('rocket'));
      expect(copied.customAvatarBase64, equals('aGVsbG8='));
      expect(copied.customAvatarPath, equals('C:/avatar.png'));
    });

    test('PeerModel isAi alias returns true for __AI_ASSISTANT__', () {
      final aiPeer = PeerModel.createAiAssistantPeer();
      expect(aiPeer.isAi, isTrue);
      expect(aiPeer.isAiAssistant, isTrue);

      final normalPeer = PeerModel(
        id: '192.168.1.100:49723',
        name: 'Normal',
        ip: '192.168.1.100',
        port: 49723,
      );
      expect(normalPeer.isAi, isFalse);
    });
  });

  group('AppPreferences Avatar Persistence Unit Tests', () {
    test('Default avatar preferences are initials with robot preset', () {
      final prefs = AppPreferences();
      expect(prefs.userAvatarType, equals('initials'));
      expect(prefs.userAvatarPreset, equals('robot'));
      expect(prefs.userAvatarCustomPath, equals(''));
      expect(prefs.userAvatarColor, equals('#3B82F6'));
    });

    test('setUserAvatar updates fields and persists to disk', () async {
      final prefs = AppPreferences();
      await prefs.setUserAvatar(
        type: 'preset',
        preset: 'fire',
        customPath: 'C:/custom.png',
        color: '#EF4444',
      );

      expect(prefs.userAvatarType, equals('preset'));
      expect(prefs.userAvatarPreset, equals('fire'));
      expect(prefs.userAvatarCustomPath, equals('C:/custom.png'));
      expect(prefs.userAvatarColor, equals('#EF4444'));

      // Reload from disk to verify persistence
      await prefs.load();
      expect(prefs.userAvatarType, equals('preset'));
      expect(prefs.userAvatarPreset, equals('fire'));
      expect(prefs.userAvatarCustomPath, equals('C:/custom.png'));
      expect(prefs.userAvatarColor, equals('#EF4444'));
    });

    test('resetToDefaults resets avatar configuration', () async {
      final prefs = AppPreferences();
      await prefs.setUserAvatar(
        type: 'custom',
        preset: 'shield',
        color: '#10B981',
      );
      prefs.resetToDefaults();

      expect(prefs.userAvatarType, equals('initials'));
      expect(prefs.userAvatarPreset, equals('robot'));
      expect(prefs.userAvatarCustomPath, equals(''));
      expect(prefs.userAvatarColor, equals('#3B82F6'));
      expect(prefs.userAvatarBase64, equals(''));
    });

    test('setUserAvatar preserves and updates userAvatarBase64', () async {
      final prefs = AppPreferences();
      await prefs.setUserAvatar(
        type: 'custom',
        customPath: 'C:/test.png',
        base64: 'dGVzdGJhc2U2NA==',
      );

      expect(prefs.userAvatarType, equals('custom'));
      expect(prefs.userAvatarBase64, equals('dGVzdGJhc2U2NA=='));

      await prefs.load();
      expect(prefs.userAvatarBase64, equals('dGVzdGJhc2U2NA=='));
    });
  });

  group('AvatarUtils Tests', () {
    test(
      'bytesToThumbnailBase64 encodes small bytes directly if fallback',
      () async {
        final testBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
        final b64 = await AvatarUtils.bytesToThumbnailBase64(testBytes);
        expect(b64, isNotNull);
        expect(base64Decode(b64!), equals(testBytes));
      },
    );

    test('decoded custom avatars keep the same bytes across rebuilds', () {
      const payload = 'aGVsbG8=';
      final first = AvatarImageCache.decode(payload);
      final second = AvatarImageCache.decode(payload);
      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
    });

    test('bytesToThumbnailBase64 returns null on empty bytes', () async {
      final b64 = await AvatarUtils.bytesToThumbnailBase64(Uint8List(0));
      expect(b64, isNull);
    });
  });

  group('Avatar Protocol & Network Wire Tests', () {
    test('buildAvatarUpdatePacket matches native BeeBEEP vCard fields', () {
      final packetBytes = ProtocolBeebeep.buildAvatarUpdatePacket(
        nickname: 'Nam',
        colorHex: '#EF4444',
        photoBase64: 'aGVsbG8=',
      );
      final msg = ProtocolBeebeep.parseMessage(utf8.decode(packetBytes));

      expect(msg, isNotNull);
      expect(msg!['header'], equals(ProtocolBeebeep.headerUser));
      expect(msg['id'], equals('16'));
      expect(msg['flags'], equals(16));
      expect(msg['text'], equals('aGVsbG8='));
      final fields = (msg['data'] as String).split('\u2028');
      expect(fields.length, greaterThanOrEqualTo(5));
      expect(fields[0], 'Nam');
      expect(fields[5], '#EF4444');
      expect(
        ProtocolBeebeep.normalizeAvatarPayload(msg),
        '#EF4444|b64:aGVsbG8=',
      );
    });

    test('native vCard without the JA marker still yields the photo', () {
      final raw = ProtocolBeebeep.packet(
        ProtocolBeebeep.headerUser,
        '16',
        flags: 16,
        text: 'aGVsbG8=',
        data: [
          'Bee',
          '',
          '',
          '',
          '',
          '#112233',
          '',
          '',
          'N',
          '',
        ].join('\u2028'),
      );
      final msg = ProtocolBeebeep.parseMessage(utf8.decode(raw))!;
      expect(
        ProtocolBeebeep.normalizeAvatarPayload(msg),
        '#112233|b64:aGVsbG8=',
      );
    });

    test('legacy JA avatar packets remain readable', () {
      final raw = ProtocolBeebeep.packet(
        ProtocolBeebeep.headerUser,
        '15',
        flags: 16,
        text: '#EF4444|preset:rocket',
        data: 'avatar:#EF4444|preset:rocket',
      );
      final msg = ProtocolBeebeep.parseMessage(utf8.decode(raw))!;
      expect(
        ProtocolBeebeep.normalizeAvatarPayload(msg),
        '#EF4444|preset:rocket',
      );
    });

    test('preset metadata is carried in the vCard info field', () {
      final raw = ProtocolBeebeep.buildAvatarUpdatePacket(
        nickname: 'Nam',
        colorHex: '#EF4444',
        jaPayload: '#EF4444|preset:rocket',
      );
      final msg = ProtocolBeebeep.parseMessage(utf8.decode(raw))!;
      expect(msg['text'], isEmpty);
      expect(
        ProtocolBeebeep.normalizeAvatarPayload(msg),
        '#EF4444|preset:rocket',
      );
    });

    test(
      'buildGroupPacket and groupMetadata encode and decode group avatar payload',
      () {
        final now = DateTime.utc(2026, 9, 22, 10, 0, 0);
        final packetBytes = ProtocolBeebeep.buildGroupPacket(
          groupId: 'grp123',
          name: 'Team Dev',
          updatedAt: now,
          members: [
            ['Peer1', 'peer1', 'hash1', ''],
          ],
          avatarPayload: '#6366F1|preset:code',
        );

        final raw = utf8.decode(packetBytes);
        final msg = ProtocolBeebeep.parseMessage(raw);
        expect(msg, isNotNull);

        final meta = ProtocolBeebeep.groupMetadata(msg!);
        expect(meta, isNotNull);
        expect(meta!.id, equals('grp123'));
        expect(meta.name, equals('Team Dev'));
        expect(meta.avatarPayload, equals('#6366F1|preset:code'));
      },
    );
  });

  group('GroupModel and PeerModel Avatar Sync Tests', () {
    test('GroupModel toJson and fromJson preserve avatar fields', () {
      final group = GroupModel(
        id: 'group_test_1',
        name: 'Engineering',
        memberIds: ['192.168.1.10:6475'],
        color: const Color(0xFF10B981),
        avatarPreset: 'rocket',
        customAvatarPath: 'C:/group.png',
        customAvatarBase64: 'Z3JvdXBiYXNlNjQ=',
      );

      final json = group.toJson();
      expect(json['avatarPreset'], equals('rocket'));
      expect(json['customAvatarPath'], equals('C:/group.png'));
      expect(json['customAvatarBase64'], equals('Z3JvdXBiYXNlNjQ='));

      final restored = GroupModel.fromJson(json);
      expect(restored.avatarPreset, equals('rocket'));
      expect(restored.customAvatarPath, equals('C:/group.png'));
      expect(restored.customAvatarBase64, equals('Z3JvdXBiYXNlNjQ='));
      expect(restored.color, equals(const Color(0xFF10B981)));
    });

    test('PeerModel.fromGroup propagates avatar fields', () {
      final group = GroupModel(
        id: 'group_test_2',
        name: 'Designers',
        memberIds: ['192.168.1.20:6475'],
        color: const Color(0xFFEC4899),
        avatarPreset: 'palette',
        customAvatarBase64: 'ZGVzaWduYjY0',
      );

      final peer = PeerModel.fromGroup(group);
      expect(peer.isGroup, isTrue);
      expect(peer.avatarColor, equals(const Color(0xFFEC4899)));
      expect(peer.avatarPreset, equals('palette'));
      expect(peer.customAvatarBase64, equals('ZGVzaWduYjY0'));
    });
  });

  group('AppAvatar Group Widget Tests', () {
    testWidgets('AppAvatar renders preset icon for group with avatarPreset', (
      tester,
    ) async {
      final groupPeer = PeerModel(
        id: 'group_1',
        name: 'Gamers',
        ip: '',
        port: 0,
        isGroup: true,
        avatarPreset: 'game',
        avatarColor: const Color(0xFF8B5CF6),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppAvatar(peer: groupPeer, size: 48)),
        ),
      );

      expect(find.byIcon(Icons.sports_esports_rounded), findsOneWidget);
    });

    testWidgets(
      'AppAvatar renders default groups icon for group without preset or image',
      (tester) async {
        final groupPeer = PeerModel(
          id: 'group_2',
          name: 'General',
          ip: '',
          port: 0,
          isGroup: true,
          avatarColor: const Color(0xFF3B82F6),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AppAvatar(peer: groupPeer, size: 48)),
          ),
        );

        expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
      },
    );
  });

  group('Avatar regression fixes', () {
    test('switching a group avatar to a preset clears the old image', () async {
      MessengerCoordinator.customGroupsFileForTesting = File(
        '${tempDir.path}/groups.json',
      );
      final coordinator = MessengerCoordinator();
      addTearDown(coordinator.dispose);
      await coordinator.createGroup('Team', const [
        '192.0.2.1:6475',
      ], customAvatarPath: '${tempDir.path}/missing.png');
      coordinator.groups.single.customAvatarBase64 = 'b2xk';
      coordinator.groups.single.customAvatarPath = '${tempDir.path}/old.png';

      await coordinator.updateGroupAvatar(
        coordinator.groups.single.id,
        preset: 'rocket',
        color: const Color(0xFFEF4444),
      );

      final group = coordinator.groups.single;
      expect(group.avatarPreset, 'rocket');
      expect(group.customAvatarBase64, isNull);
      expect(group.customAvatarPath, isNull);
    });

    test('keeping a remote group image survives a color-only save', () async {
      MessengerCoordinator.customGroupsFileForTesting = File(
        '${tempDir.path}/groups.json',
      );
      final coordinator = MessengerCoordinator();
      addTearDown(coordinator.dispose);
      await coordinator.createGroup('Team', const ['192.0.2.1:6475']);
      await coordinator.updateGroupAvatar(
        coordinator.groups.single.id,
        color: const Color(0xFF10B981),
        customBase64: 'cmVtb3Rl',
      );
      final group = coordinator.groups.single;
      expect(group.customAvatarBase64, 'cmVtb3Rl');
      expect(group.avatarPreset, isNull);
      expect(group.color.toARGB32(), const Color(0xFF10B981).toARGB32());
    });

    test('a saved custom avatar path is converted to Base64', () async {
      final image = File('${tempDir.path}/face.bin');
      await image.writeAsBytes([9, 8, 7, 6]);
      await AppPreferences().setUserAvatar(
        type: 'custom',
        customPath: image.path,
        base64: '',
      );
      MessengerCoordinator.customGroupsFileForTesting = File(
        '${tempDir.path}/groups.json',
      );
      final coordinator = MessengerCoordinator();
      addTearDown(coordinator.dispose);
      await coordinator.migratePersonalAvatarIfNeeded();
      expect(AppPreferences().userAvatarBase64, base64Encode([9, 8, 7, 6]));
    });

    testWidgets('remote group avatar preview uses the received Base64', (
      tester,
    ) async {
      final lang = LanguageProvider();
      final theme = ThemeProvider(initialMode: 'dark');
      addTearDown(lang.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LanguageProvider>.value(value: lang),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: const MaterialApp(
            home: AvatarPickerDialog(
              targetGroupId: 'group_remote',
              groupName: 'Team',
              initialCustomBase64: 'YQ==',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(AvatarPresets.getIcon('game')), findsWidgets);
    });
  });

  group('Group Permission and Avatar Synchronization Tests', () {
    testWidgets('AppAvatar renders Image.asset for AI Peer with avatarAsset', (
      tester,
    ) async {
      final aiPeer = PeerModel.createAiAssistantPeer();
      expect(aiPeer.avatarAsset, 'assets/ai_avatar.png');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppAvatar(peer: aiPeer, size: 40)),
        ),
      );

      final imgFinder = find.byType(Image);
      expect(imgFinder, findsOneWidget);
      final image = tester.widget<Image>(imgFinder);
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName, 'assets/ai_avatar.png');
    });

    test(
      'GroupModel creatorId and adminIds serialization and role checking',
      () {
        final group = GroupModel(
          id: 'group_creatorhash_123456789',
          name: 'Alpha Group',
          memberIds: ['peer1:6475', 'peer2:6475'],
          creatorId: 'creatorhash123456',
          adminIds: ['creatorhash123456', 'coadminhash'],
        );

        expect(group.isCreator('creatorhash123456'), isTrue);
        expect(group.isAdmin('creatorhash123456'), isTrue);
        expect(group.isAdmin('coadminhash'), isTrue);
        expect(group.isAdmin('regular_member'), isFalse);

        final json = group.toJson();
        expect(json['creatorId'], 'creatorhash123456');
        expect(json['adminIds'], ['creatorhash123456', 'coadminhash']);

        final restored = GroupModel.fromJson(json);
        expect(restored.creatorId, 'creatorhash123456');
        expect(restored.adminIds, ['creatorhash123456', 'coadminhash']);
        expect(restored.isCreator('creatorhash123456'), isTrue);
      },
    );

    test(
      'GroupModel isCreator fallback to id prefix if creatorId is omitted',
      () {
        final group = GroupModel(
          id: 'group_abcdef123456_999999',
          name: 'Legacy Group',
          memberIds: ['peer1:6475'],
        );

        expect(group.isCreator('abcdef1234567890'), isTrue);
        expect(group.isCreator('otherhash1234567'), isFalse);
      },
    );

    test('ProtocolBeebeep encodes and decodes creatorId in group packets', () {
      final packetBytes = ProtocolBeebeep.buildGroupPacket(
        groupId: 'grp_001',
        name: 'Dev Ops',
        updatedAt: DateTime.utc(2026, 9, 23, 1, 0, 0),
        creatorId: 'user_hash_owner',
        members: const [],
      );

      final raw = utf8.decode(packetBytes);
      final msg = ProtocolBeebeep.parseMessage(raw);
      expect(msg, isNotNull);

      final meta = ProtocolBeebeep.groupMetadata(msg!);
      expect(meta, isNotNull);
      expect(meta!.creatorId, 'user_hash_owner');
    });
  });

  group('AppAvatar Styling & Shape Default Tests', () {
    testWidgets('AppAvatar defaults to circular shape with colored border', (
      tester,
    ) async {
      final peer = PeerModel(
        id: 'user_1',
        name: 'Nguyen Van A',
        ip: '192.168.1.50',
        port: 6475,
        avatarColor: const Color(0xFF8B5CF6),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppAvatar(peer: peer, size: 40)),
        ),
      );

      final containerFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(containerFinder, findsWidgets);

      final outerContainer = tester.widget<Container>(containerFinder.first);
      final deco = outerContainer.decoration as BoxDecoration;
      expect(deco.shape, equals(BoxShape.circle));
      expect(
        deco.border?.top.color,
        equals(const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
      );

      final textFinder = find.text('NV');
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.color, equals(const Color(0xFF8B5CF6)));
      expect(textWidget.style?.fontWeight, equals(FontWeight.bold));
    });

    testWidgets('AppAvatar.local defaults to circular shape', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AppAvatar.local(size: 40))),
      );

      final containerFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(containerFinder, findsWidgets);
    });

    testWidgets(
      'AppAvatar preset icon styling uses translucent background and matching icon color',
      (tester) async {
        final peer = PeerModel(
          id: 'user_2',
          name: 'Gamer User',
          ip: '192.168.1.51',
          port: 6475,
          avatarPreset: 'game',
          avatarColor: const Color(0xFFEF4444),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AppAvatar(peer: peer, size: 40)),
          ),
        );

        final iconFinder = find.byIcon(Icons.sports_esports_rounded);
        expect(iconFinder, findsOneWidget);
        final iconWidget = tester.widget<Icon>(iconFinder);
        expect(iconWidget.color, equals(const Color(0xFFEF4444)));
      },
    );
  });
}
