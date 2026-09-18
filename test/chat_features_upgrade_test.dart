import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';

void main() {
  group('Chat Upgrade Protocol Tests', () {
    test('Typing packet encoding and parsing for BeeBEEP compatibility', () {
      // 1. Typing start
      final typingStartBytes = ProtocolBeebeep.buildTypingPacket(
        isTyping: true,
      );
      expect(typingStartBytes, isNotEmpty);
      final rawStart = utf8.decode(typingStartBytes);
      final parsedStart = ProtocolBeebeep.parseMessage(rawStart);

      expect(parsedStart, isNotNull);
      expect(parsedStart!['header'], equals(ProtocolBeebeep.headerUser));
      expect(parsedStart['id'], equals('${ProtocolBeebeep.idWritingMessage}'));
      expect(parsedStart['text'], equals('*'));
      expect(parsedStart['flags'], equals(3)); // flagUserWriting (2) | 1

      // 2. Typing stop
      final typingStopBytes = ProtocolBeebeep.buildTypingPacket(
        isTyping: false,
      );
      expect(typingStopBytes, isNotEmpty);
      final rawStop = utf8.decode(typingStopBytes);
      final parsedStop = ProtocolBeebeep.parseMessage(rawStop);

      expect(parsedStop, isNotNull);
      expect(parsedStop!['header'], equals(ProtocolBeebeep.headerUser));
      expect(parsedStop['id'], equals('${ProtocolBeebeep.idWritingMessage}'));
      expect(parsedStop['text'], equals(''));
      expect(parsedStop['flags'], equals(1));
    });

    test('Read receipt packet encoding and parsing', () {
      const msgId = 'msg_test_98765';
      final readBytes = ProtocolBeebeep.buildReadPacket(msgId);
      expect(readBytes, isNotEmpty);
      final rawRead = utf8.decode(readBytes);
      final parsedRead = ProtocolBeebeep.parseMessage(rawRead);

      expect(parsedRead, isNotNull);
      expect(parsedRead!['header'], equals(ProtocolBeebeep.headerRead));
      expect(parsedRead['text'], equals(msgId));
    });

    test('Message revocation packet encoding and parsing', () {
      const msgId = 'msg_test_revoke_123';
      final revokeBytes = ProtocolBeebeep.buildRevokePacket(msgId);
      expect(revokeBytes, isNotEmpty);
      final rawRevoke = utf8.decode(revokeBytes);
      final parsedRevoke = ProtocolBeebeep.parseMessage(rawRevoke);

      expect(parsedRevoke, isNotNull);
      expect(parsedRevoke!['header'], equals(ProtocolBeebeep.headerRevoke));
      expect(parsedRevoke['text'], equals(msgId));
    });
  });

  group('MessageModel Upgrade State Tests', () {
    test('Message revocation state and attachment visibility', () {
      final msg = MessageModel(
        id: 'msg_test_file_001',
        senderId: 'me',
        senderName: 'TestUser',
        recipientId: 'peer_1',
        text: '📁 Document.pdf',
        isMine: true,
        fileAttachment: FileAttachmentInfo(
          fileName: 'Document.pdf',
          fileSize: 1024 * 1024,
          localPath: 'C:\\test\\Document.pdf',
          isTransferComplete: true,
        ),
      );

      expect(msg.isRevoked, isFalse);
      expect(msg.revokedAt, isNull);
      expect(msg.hasAttachment, isTrue);

      // Thu hồi tin nhắn
      final now = DateTime.now();
      msg.isRevoked = true;
      msg.revokedAt = now;

      expect(msg.isRevoked, isTrue);
      expect(msg.revokedAt, equals(now));
      expect(msg.hasAttachment, isFalse); // Attachment must be hidden
    });

    test('MessageStatus transitions for seen status', () {
      final msg = MessageModel(
        id: 'msg_status_001',
        senderId: 'me',
        senderName: 'Sender',
        recipientId: 'receiver',
        text: 'Hello!',
        isMine: true,
        status: MessageStatus.sending,
      );

      expect(msg.status, equals(MessageStatus.sending));

      msg.status = MessageStatus.delivered;
      expect(msg.status, equals(MessageStatus.delivered));

      msg.status = MessageStatus.read;
      expect(msg.status, equals(MessageStatus.read));
    });
  });

  group('Localization Completeness for Chat Upgrades', () {
    test('All new upgrade keys exist in vi, en, zh', () {
      final provider = LanguageProvider();
      const testKeys = [
        'messageRevoked',
        'revokeMessage',
        'revokeConfirm',
        'typing',
        'seen',
        'newMessageNotification',
        'cancel',
        'copy',
      ];

      for (final lang in AppLanguage.values) {
        provider.setLanguage(lang);
        for (final key in testKeys) {
          final translated = provider.tr(key);
          expect(
            translated,
            isNot(equals(key)),
            reason: 'Key "$key" should be translated for language ${lang.code}',
          );
          expect(translated, isNotEmpty);
        }
      }
    });
  });
}
