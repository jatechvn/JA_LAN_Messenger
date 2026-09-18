import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ChatHistoryService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_history_test_');
    service = ChatHistoryService();
    service.setCustomDirectoryForTesting(tempDir);
  });

  tearDown(() async {
    service.setCustomDirectoryForTesting(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MessageModel Serialization Tests', () {
    test('Roundtrip serialization of plain text message', () {
      final now = DateTime.now();
      final msg = MessageModel(
        id: 'msg_1',
        senderId: 'user_a',
        senderName: 'Alice',
        recipientId: 'user_b',
        text: 'Hello, World!',
        timestamp: now,
        isMine: true,
        status: MessageStatus.delivered,
        isRevoked: false,
        aiModelTag: null,
        thinkingContent: null,
      );

      final json = msg.toJson();
      final restored = MessageModel.fromJson(json);

      expect(restored.id, equals(msg.id));
      expect(restored.senderId, equals(msg.senderId));
      expect(restored.senderName, equals(msg.senderName));
      expect(restored.recipientId, equals(msg.recipientId));
      expect(restored.text, equals(msg.text));
      expect(
        restored.timestamp.millisecondsSinceEpoch,
        equals(now.millisecondsSinceEpoch),
      );
      expect(restored.isMine, isTrue);
      expect(restored.status, equals(MessageStatus.delivered));
      expect(restored.isRevoked, isFalse);
      expect(restored.fileAttachment, isNull);
    });

    test('Roundtrip serialization of message with file attachment', () {
      final msg = MessageModel(
        id: 'msg_file_1',
        senderId: 'user_a',
        senderName: 'Alice',
        recipientId: 'user_b',
        text: '📁 Document.pdf',
        isMine: false,
        status: MessageStatus.read,
        fileAttachment: const FileAttachmentInfo(
          fileName: 'Document.pdf',
          fileSize: 1048576,
          localPath: 'C:\\Downloads\\Document.pdf',
          isTransferComplete: true,
        ),
      );

      final json = msg.toJson();
      final restored = MessageModel.fromJson(json);

      expect(restored.hasAttachment, isTrue);
      expect(restored.fileAttachment, isNotNull);
      expect(restored.fileAttachment!.fileName, equals('Document.pdf'));
      expect(restored.fileAttachment!.fileSize, equals(1048576));
      expect(
        restored.fileAttachment!.localPath,
        equals('C:\\Downloads\\Document.pdf'),
      );
      expect(restored.fileAttachment!.isTransferComplete, isTrue);
    });

    test(
      'Roundtrip serialization of AI message with thinking and model tag',
      () {
        final msg = MessageModel(
          id: 'ai_msg_1',
          senderId: '__AI_ASSISTANT__',
          senderName: 'JA-AI Assistant',
          recipientId: 'me',
          text: 'The solution is 42.',
          isMine: false,
          status: MessageStatus.delivered,
          aiModelTag: 'qwen3.5:4b',
          thinkingContent: 'Let me think about the meaning of life...',
        );

        final json = msg.toJson();
        final restored = MessageModel.fromJson(json);

        expect(restored.aiModelTag, equals('qwen3.5:4b'));
        expect(
          restored.thinkingContent,
          equals('Let me think about the meaning of life...'),
        );
        expect(restored.isStreaming, isFalse);
      },
    );
  });

  group('ChatHistoryService Storage & I/O Tests', () {
    test('Filename sanitization converts invalid characters', () {
      expect(
        ChatHistoryService.sanitizeConversationId('192.168.1.50:64738'),
        equals('192.168.1.50_64738'),
      );
      expect(
        ChatHistoryService.sanitizeConversationId('group/test:name?*'),
        equals('group_test_name__'),
      );
      expect(
        ChatHistoryService.sanitizeConversationId('__AI_ASSISTANT__'),
        equals('__AI_ASSISTANT__'),
      );
    });

    test('Immediate save and load preserves messages correctly', () async {
      final messages = <MessageModel>[
        MessageModel(
          id: '1',
          senderId: 'p1',
          senderName: 'Bob',
          recipientId: 'me',
          text: 'Message 1',
          isMine: false,
        ),
        MessageModel(
          id: '2',
          senderId: 'me',
          senderName: 'Me',
          recipientId: 'p1',
          text: 'Message 2',
          isMine: true,
        ),
      ];

      await service.saveImmediately('peer_123', messages);

      final loaded = await service.loadConversation('peer_123');
      expect(loaded.length, equals(2));
      expect(loaded[0].text, equals('Message 1'));
      expect(loaded[1].text, equals('Message 2'));
    });

    test('Load non-existent conversation returns empty list', () async {
      final loaded = await service.loadConversation('non_existent');
      expect(loaded, isEmpty);
    });

    test(
      'Load all conversations loads multiple files with preserved conversationIds',
      () async {
        final peer1Msgs = <MessageModel>[
          MessageModel(
            id: '1',
            senderId: '192.168.1.10:64738',
            senderName: 'Peer 1',
            recipientId: 'me',
            text: 'From Peer 1',
            isMine: false,
          ),
        ];

        final aiMsgs = <MessageModel>[
          MessageModel(
            id: '2',
            senderId: '__AI_ASSISTANT__',
            senderName: 'AI',
            recipientId: 'me',
            text: 'From AI',
            isMine: false,
          ),
        ];

        await service.saveImmediately('192.168.1.10:64738', peer1Msgs);
        await service.saveImmediately('__AI_ASSISTANT__', aiMsgs);

        final all = await service.loadAllConversations();
        expect(all.containsKey('192.168.1.10:64738'), isTrue);
        expect(all.containsKey('__AI_ASSISTANT__'), isTrue);
        expect(all['192.168.1.10:64738']!.first.text, equals('From Peer 1'));
        expect(all['__AI_ASSISTANT__']!.first.text, equals('From AI'));
      },
    );

    test('Delete single conversation removes file from disk', () async {
      final msgs = <MessageModel>[
        MessageModel(
          id: '1',
          senderId: 'p1',
          senderName: 'Alice',
          recipientId: 'me',
          text: 'To be deleted',
          isMine: false,
        ),
      ];

      await service.saveImmediately('to_delete', msgs);
      expect((await service.loadConversation('to_delete')).length, equals(1));

      await service.deleteConversation('to_delete');
      expect((await service.loadConversation('to_delete')), isEmpty);
    });

    test('Clear all history removes all json files in folder', () async {
      await service.saveImmediately('conv_1', <MessageModel>[
        MessageModel(
          id: '1',
          senderId: 'a',
          senderName: 'A',
          recipientId: 'b',
          text: 'test 1',
          isMine: false,
        ),
      ]);
      await service.saveImmediately('conv_2', <MessageModel>[
        MessageModel(
          id: '2',
          senderId: 'b',
          senderName: 'B',
          recipientId: 'a',
          text: 'test 2',
          isMine: true,
        ),
      ]);

      expect((await service.loadAllConversations()).length, equals(2));

      await service.clearAllHistory();

      expect((await service.loadAllConversations()), isEmpty);
      expect(await service.getHistorySizeBytes(), equals(0));
    });

    test(
      'Sliding window caps storage at maxHistoryPerConversation messages',
      () async {
        final msgs = List<MessageModel>.generate(
          1050,
          (i) => MessageModel(
            id: 'msg_$i',
            senderId: 'user',
            senderName: 'User',
            recipientId: 'me',
            text: 'Message $i',
            isMine: false,
          ),
        );

        await service.saveImmediately('large_conv', msgs);
        final loaded = await service.loadConversation('large_conv');

        expect(loaded.length, equals(1000));
        // Truncation keeps the last 1000 messages (from 50 to 1049)
        expect(loaded.first.id, equals('msg_50'));
        expect(loaded.last.id, equals('msg_1049'));
      },
    );

    test('Format bytes utility formats disk size correctly', () {
      expect(ChatHistoryService.formatBytes(500), equals('500 B'));
      expect(ChatHistoryService.formatBytes(2048), equals('2.0 KB'));
      expect(
        ChatHistoryService.formatBytes(5 * 1024 * 1024),
        equals('5.00 MB'),
      );
    });

    test('Debounced scheduleSave eventually writes to disk', () async {
      final msgs = <MessageModel>[
        MessageModel(
          id: 'debounced_1',
          senderId: 'a',
          senderName: 'A',
          recipientId: 'b',
          text: 'Debounced text',
          isMine: false,
        ),
      ];

      service.scheduleSave('debounced_conv', msgs);

      // Wait 850ms for debounce timer (500ms) and disk I/O to fire safely under load
      await Future.delayed(const Duration(milliseconds: 850));

      final loaded = await service.loadConversation('debounced_conv');
      expect(loaded.length, equals(1));
      expect(loaded.first.text, equals('Debounced text'));
    });
  });
}
