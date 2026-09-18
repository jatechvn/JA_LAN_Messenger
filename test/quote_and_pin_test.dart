import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

void main() {
  group('Quote & Pin Messages Unit Tests', () {
    test('MessageModel quote & pin serialization and deserialization', () {
      final original = MessageModel(
        id: 'msg-123',
        senderId: 'alice-id',
        senderName: 'Alice',
        recipientId: 'bob-id',
        text: 'This is a replied message',
        isMine: true,
        replyToId: 'target-001',
        replyToSender: 'Bob',
        replyToText: 'Original hello message',
        isPinned: true,
      );

      expect(original.isReply, isTrue);
      expect(original.isPinned, isTrue);
      expect(original.conversationId, 'bob-id');

      final json = original.toJson();
      expect(json['replyToId'], 'target-001');
      expect(json['replyToSender'], 'Bob');
      expect(json['replyToText'], 'Original hello message');
      expect(json['isPinned'], isTrue);

      final restored = MessageModel.fromJson(json);
      expect(restored.id, 'msg-123');
      expect(restored.senderName, 'Alice');
      expect(restored.text, 'This is a replied message');
      expect(restored.replyToId, 'target-001');
      expect(restored.replyToSender, 'Bob');
      expect(restored.replyToText, 'Original hello message');
      expect(restored.isPinned, isTrue);
      expect(restored.isReply, isTrue);
      expect(restored.conversationId, 'bob-id');
    });

    test('PeerModel displayName never returns ???', () {
      // Case 1: name is '???' with valid hostname and account
      final peer1 = PeerModel(
        id: '192.168.1.100:64738',
        name: '???',
        accountName: 'engineering_pc',
        hostname: 'ENG-WORKSTATION',
        ip: '192.168.1.100',
        port: 64738,
      );
      expect(peer1.displayName, isNot(contains('???')));
      expect(peer1.displayName, 'engineering_pc@ENG-WORKSTATION');

      // Case 2: name is '???' with only hostname
      final peer2 = PeerModel(
        id: '192.168.1.101:64738',
        name: '???',
        hostname: 'OFFICE-LAPTOP',
        ip: '192.168.1.101',
        port: 64738,
      );
      expect(peer2.displayName, 'OFFICE-LAPTOP');

      // Case 3: name is '???' with only account
      final peer3 = PeerModel(
        id: '192.168.1.102:64738',
        name: '???',
        accountName: 'john_doe',
        ip: '192.168.1.102',
        port: 64738,
      );
      expect(peer3.displayName, 'john_doe (192.168.1.102)');

      // Case 4: everything is ??? or empty -> fallback to IP
      final peer4 = PeerModel(
        id: '192.168.1.103:64738',
        name: '???',
        accountName: '???',
        hostname: '???',
        ip: '192.168.1.103',
        port: 64738,
      );
      expect(peer4.displayName, '192.168.1.103');

      // Case 5: customNickname always takes highest priority even if name was ???
      peer4.customNickname = 'My Server';
      expect(peer4.displayName, 'My Server');
    });

    test(
      'KnownDevicesRegistry rejects ??? as a valid custom nickname or name',
      () {
        final tempDir = Directory.systemTemp.createTempSync('ja_known_test_');
        final testFilePath = '${tempDir.path}\\test_known_devices.json';
        final registry = KnownDevicesRegistry(testFilePath);

        // Register initial good name
        registry.recordDevice(
          identityKey: '192.168.1.10:64738',
          username: 'Alice_PC',
          ip: '192.168.1.10',
        );
        expect(registry.devices['192.168.1.10:64738']?.username, 'Alice_PC');

        // Try updating with ??? username - should NOT overwrite good name Alice_PC
        registry.recordDevice(
          identityKey: '192.168.1.10:64738',
          username: '???',
          ip: '192.168.1.10',
        );
        expect(registry.devices['192.168.1.10:64738']?.username, 'Alice_PC');

        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      },
    );

    test('MessengerCoordinator pin and unpin operations', () {
      final coordinator = MessengerCoordinator();
      final peer = PeerModel(
        id: 'peer-test-1',
        name: 'TestPeer',
        ip: '192.168.1.88',
        port: 64738,
      );
      coordinator.selectPeer(peer);

      final msg1 = MessageModel(
        id: 'msg-01',
        senderId: 'peer-test-1',
        senderName: 'TestPeer',
        recipientId: 'my-id',
        text: 'Hello, important announcement!',
        isMine: false,
      );
      final msg2 = MessageModel(
        id: 'msg-02',
        senderId: 'peer-test-1',
        senderName: 'TestPeer',
        recipientId: 'my-id',
        text: 'Normal casual chat',
        isMine: false,
      );

      // Inject messages
      coordinator.conversationsMap['peer-test-1'] = [msg1, msg2];

      // Initially no pinned messages
      expect(coordinator.getPinnedMessages('peer-test-1'), isEmpty);

      // Pin msg1
      coordinator.togglePinMessage('peer-test-1', 'msg-01');
      expect(msg1.isPinned, isTrue);
      final pinnedList = coordinator.getPinnedMessages('peer-test-1');
      expect(pinnedList.length, 1);
      expect(pinnedList.first.id, 'msg-01');

      // Unpin msg1
      coordinator.togglePinMessage('peer-test-1', 'msg-01');
      expect(msg1.isPinned, isFalse);
      expect(coordinator.getPinnedMessages('peer-test-1'), isEmpty);

      coordinator.dispose();
    });

    test('Localization keys for Quote and Pin exist in VI, EN, ZH', () {
      final lang = LanguageProvider();

      const requiredKeys = [
        'quote',
        'replyingTo',
        'cancelReply',
        'pinMessage',
        'unpinMessage',
        'pinnedMessage',
        'pinnedMessagesCount',
        'messagePinnedToast',
        'messageUnpinnedToast',
      ];

      for (final code in [AppLanguage.vi, AppLanguage.en, AppLanguage.zh]) {
        lang.setLanguage(code);
        for (final key in requiredKeys) {
          final translated = lang.tr(key);
          expect(translated, isNotEmpty, reason: '$code missing key $key');
          expect(
            translated,
            isNot(equals(key)),
            reason: '$code key $key not translated',
          );
        }
      }
    });
  });
}
