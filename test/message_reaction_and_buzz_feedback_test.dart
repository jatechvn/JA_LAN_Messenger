import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/contact_profile_dialog.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessageModel Reaction Unit Tests', () {
    test('Initializes with empty reactions map', () {
      final message = MessageModel(
        id: 'msg-1',
        senderId: 'user1',
        senderName: 'Alice',
        recipientId: 'user2',
        text: 'Hello world',
        isMine: true,
      );

      expect(message.reactions, isEmpty);
      expect(message.hasUserReacted('👍', 'Alice'), isFalse);
    });

    test(
      'addReaction, removeReaction, and hasUserReacted operate correctly',
      () {
        final message = MessageModel(
          id: 'msg-2',
          senderId: 'user1',
          senderName: 'Alice',
          recipientId: 'user2',
          text: 'Testing reactions',
          isMine: true,
        );

        // Add reactions
        message.addReaction('👍', 'Alice');
        message.addReaction('👍', 'Bob');
        message.addReaction('❤️', 'Alice');

        expect(message.reactions['👍'], equals(['Alice', 'Bob']));
        expect(message.reactions['❤️'], equals(['Alice']));
        expect(message.hasUserReacted('👍', 'Alice'), isTrue);
        expect(message.hasUserReacted('👍', 'Bob'), isTrue);
        expect(message.hasUserReacted('👍', 'Charlie'), isFalse);
        expect(message.hasUserReacted('❤️', 'Alice'), isTrue);

        // Prevent duplicate additions
        message.addReaction('👍', 'Alice');
        expect(message.reactions['👍'], equals(['Alice', 'Bob']));

        // Remove reactions
        message.removeReaction('👍', 'Alice');
        expect(message.hasUserReacted('👍', 'Alice'), isFalse);
        expect(message.reactions['👍'], equals(['Bob']));

        // Removing the last user removes the emoji entry
        message.removeReaction('❤️', 'Alice');
        expect(message.reactions.containsKey('❤️'), isFalse);
      },
    );

    test('toggleReaction toggles presence correctly', () {
      final message = MessageModel(
        id: 'msg-3',
        senderId: 'user1',
        senderName: 'Alice',
        recipientId: 'user2',
        text: 'Toggle test',
        isMine: true,
      );

      // First toggle adds
      final added = message.toggleReaction('🔥', 'Alice');
      expect(added, isTrue);
      expect(message.hasUserReacted('🔥', 'Alice'), isTrue);
      expect(message.reactions['🔥'], equals(['Alice']));

      // Second toggle removes
      final removed = message.toggleReaction('🔥', 'Alice');
      expect(removed, isFalse);
      expect(message.hasUserReacted('🔥', 'Alice'), isFalse);
      expect(message.reactions.containsKey('🔥'), isFalse);
    });

    test('MessageModel toJson and fromJson preserves reactions', () {
      final original = MessageModel(
        id: 'msg-serial',
        senderId: 'user1',
        senderName: 'Alice',
        recipientId: 'user2',
        text: 'Serialized reactions',
        isMine: true,
        reactions: {
          '👍': ['Alice', 'Bob'],
          '🎉': ['Charlie'],
        },
      );

      final json = original.toJson();
      expect(json['reactions'], isNotNull);
      expect((json['reactions'] as Map)['👍'], equals(['Alice', 'Bob']));
      expect((json['reactions'] as Map)['🎉'], equals(['Charlie']));

      final restored = MessageModel.fromJson(json);
      expect(restored.id, equals('msg-serial'));
      expect(restored.reactions['👍'], equals(['Alice', 'Bob']));
      expect(restored.reactions['🎉'], equals(['Charlie']));
      expect(restored.hasUserReacted('👍', 'Bob'), isTrue);
    });
  });

  group('ProtocolBeebeep Reaction Packets Tests', () {
    test('buildReactionPacket and parseReactionPacket for add reaction', () {
      final packetBytes = ProtocolBeebeep.buildReactionPacket(
        messageId: 'msg-abc-123',
        emoji: '👍',
        action: 'add',
        senderName: 'Workstation-01',
      );

      expect(packetBytes, isNotEmpty);
      final rawStr = utf8.decode(packetBytes);
      final parsed = ProtocolBeebeep.parseMessage(rawStr);

      expect(parsed, isNotNull);
      expect(parsed!['header'], equals(ProtocolBeebeep.headerReaction));

      final reactionData = ProtocolBeebeep.parseReactionPacket(parsed);
      expect(reactionData, isNotNull);
      expect(reactionData!['messageId'], equals('msg-abc-123'));
      expect(reactionData['emoji'], equals('👍'));
      expect(reactionData['action'], equals('add'));
      expect(reactionData['senderName'], equals('Workstation-01'));
    });

    test('buildReactionPacket and parseReactionPacket for remove reaction', () {
      final packetBytes = ProtocolBeebeep.buildReactionPacket(
        messageId: 'msg-def-456',
        emoji: '❤️',
        action: 'remove',
        senderName: 'Workstation-02',
      );

      final rawStr = utf8.decode(packetBytes);
      final parsed = ProtocolBeebeep.parseMessage(rawStr);
      expect(parsed, isNotNull);

      final reactionData = ProtocolBeebeep.parseReactionPacket(parsed!);
      expect(reactionData, isNotNull);
      expect(reactionData!['messageId'], equals('msg-def-456'));
      expect(reactionData['emoji'], equals('❤️'));
      expect(reactionData['action'], equals('remove'));
      expect(reactionData['senderName'], equals('Workstation-02'));
    });
  });

  group('MessengerCoordinator Reaction & Buzz Sender History Tests', () {
    late Directory tempDir;
    late File prefFile;
    late ChatHistoryService history;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('msg_reaction_test_');
      prefFile = File('${tempDir.path}\\prefs.json');
      AppPreferences().setCustomFileForTesting(prefFile);
      history = ChatHistoryService();
      history.setCustomDirectoryForTesting(tempDir);
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      history.setCustomDirectoryForTesting(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'sendBuzz inserts buzz message into sender conversation and updates peer lastMessage',
      () async {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final targetPeer = PeerModel(
          id: '192.168.1.100:6475',
          name: 'Peer Bob',
          ip: '192.168.1.100',
          port: 6475,
          status: PeerStatus.online,
        );
        coordinator.peersMap[targetPeer.id] = targetPeer;
        coordinator.selectPeer(targetPeer);

        // Initial messages are empty
        expect(coordinator.conversationsMap[targetPeer.id], isNull);

        // Send buzz
        await coordinator.sendBuzz();

        final msgs = coordinator.conversationsMap[targetPeer.id];
        expect(msgs, isNotNull);
        expect(msgs!.length, equals(1));
        final buzzMsg = msgs.first;
        expect(buzzMsg.isMine, isTrue);
        expect(buzzMsg.text, contains('🔔'));
        expect(buzzMsg.text, contains('Bob'));
        expect(targetPeer.lastMessage, equals(buzzMsg.text));
      },
    );

    test(
      'handleIncomingReaction adds and removes reaction correctly in conversation',
      () async {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final testPeer = PeerModel(
          id: '192.168.1.101:6475',
          name: 'Peer Alice',
          ip: '192.168.1.101',
          port: 6475,
          status: PeerStatus.online,
        );
        coordinator.peersMap[testPeer.id] = testPeer;

        final message = MessageModel(
          id: 'msg-test-reaction-1',
          senderId: 'me',
          senderName: coordinator.localUsername,
          recipientId: testPeer.id,
          text: 'Check this feature out!',
          isMine: true,
        );

        final unrelated = MessageModel(
          id: message.id,
          senderId: 'me',
          senderName: 'Me',
          recipientId: 'other-peer',
          text: 'Unrelated',
          isMine: true,
        );
        coordinator.conversationsMap['other-peer'] = [unrelated];
        final messages = coordinator.conversationsMap.putIfAbsent(
          testPeer.id,
          () => [],
        );
        messages.add(message);

        // Peer reacts with 👍
        coordinator.handleIncomingReaction(
          '192.168.1.101:6475',
          message.id,
          '👍',
          'add',
          'Peer Alice',
        );

        expect(message.reactions['👍'], equals(['Peer Alice']));
        expect(unrelated.reactions, isEmpty);
        expect(message.hasUserReacted('👍', 'Peer Alice'), isTrue);

        // Peer removes reaction
        coordinator.handleIncomingReaction(
          '192.168.1.101:6475',
          message.id,
          '👍',
          'remove',
          'Peer Alice',
        );

        expect(message.reactions.containsKey('👍'), isFalse);
      },
    );

    test(
      'setPeerNickname updates customNickname and resets properly',
      () async {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peer = PeerModel(
          id: '192.168.1.102:6475',
          name: 'Desktop-Workstation-XYZ',
          ip: '192.168.1.102',
          port: 6475,
          status: PeerStatus.online,
        );
        coordinator.peersMap[peer.id] = peer;

        expect(peer.displayName, equals('Desktop-Workstation-XYZ'));

        // Set custom nickname
        coordinator.setPeerNickname(peer.id, 'Sếp Hùng');
        expect(peer.customNickname, equals('Sếp Hùng'));
        expect(peer.displayName, equals('Sếp Hùng'));

        // Reset nickname with null
        coordinator.setPeerNickname(peer.id, null);
        expect(peer.customNickname, isNull);
        expect(peer.displayName, equals('Desktop-Workstation-XYZ'));

        // Reset nickname with empty string
        coordinator.setPeerNickname(peer.id, '   ');
        expect(peer.customNickname, isNull);
        expect(peer.displayName, equals('Desktop-Workstation-XYZ'));
      },
    );
  });

  group('Localization Keys for Nickname, Buzz, and Reactions', () {
    test('Keys exist and format correctly across vi, en, zh', () {
      final lang = LanguageProvider();
      const keys = [
        'buzzSent',
        'editNickname',
        'nicknameHint',
        'resetDefaultName',
        'addReaction',
        'reactions',
        'quickRename',
      ];

      for (final code in ['vi', 'en', 'zh']) {
        lang.setLanguage(AppLanguage.fromCode(code));
        for (final key in keys) {
          final translated = lang.tr(key);
          expect(
            translated,
            isNot(equals(key)),
            reason: 'Key "$key" should exist in "$code"',
          );
        }

        // Test parameterized buzzSent
        final formattedBuzz = lang.tr('buzzSent', ['TestUser']);
        expect(formattedBuzz, contains('TestUser'));
      }
    });
  });

  group('Quick Nickname Dialog Widget Tests', () {
    testWidgets('Opens dialog, modifies nickname and saves', (tester) async {
      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      final peer = PeerModel(
        id: 'peer-test-widget',
        name: 'Nguyen Van A',
        ip: '192.168.1.88',
        port: 6475,
        status: PeerStatus.online,
      );
      coordinator.peersMap[peer.id] = peer;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showQuickNicknameDialog(
                    context: ctx,
                    coordinator: coordinator,
                    peer: peer,
                    lang: lang,
                  ),
                  child: const Text('Edit Nickname Button'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Click to open dialog
      await tester.tap(find.text('Edit Nickname Button'));
      await tester.pumpAndSettle();

      expect(find.byType(GlassDialog), findsOneWidget);
      expect(find.text(lang.tr('quickRename')), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Enter new nickname
      await tester.enterText(find.byType(TextField), 'Anh Hai IT');
      await tester.pump();

      // Tap Save
      await tester.tap(find.text(lang.tr('save')));
      await tester.pumpAndSettle();

      expect(find.byType(GlassDialog), findsNothing);
      expect(peer.customNickname, equals('Anh Hai IT'));
      expect(peer.displayName, equals('Anh Hai IT'));

      // Reopen to reset
      await tester.tap(find.text('Edit Nickname Button'));
      await tester.pumpAndSettle();

      expect(find.text(lang.tr('resetDefaultName')), findsOneWidget);
      await tester.tap(find.text(lang.tr('resetDefaultName')));
      await tester.pumpAndSettle();

      expect(peer.customNickname, isNull);
      expect(peer.displayName, equals('Nguyen Van A'));
    });
  });
}
