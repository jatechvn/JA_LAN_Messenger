import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'flush drains debounce; ordered writes and deletion never resurrect history',
    () async {
      final dir = await Directory.systemTemp.createTemp('ja_history_safe');
      final service = ChatHistoryService();
      AppPreferences().setCustomFileForTesting(File('${dir.path}/prefs.json'));
      service.setCustomDirectoryForTesting(dir);
      try {
        MessageModel message(String text) => MessageModel(
          id: text,
          senderId: 'a',
          senderName: 'A',
          recipientId: 'b',
          text: text,
          timestamp: DateTime.now(),
          isMine: true,
        );
        service.scheduleSave('chat', [
          message('pending'),
        ], delay: const Duration(hours: 1));
        await service.flush();
        expect((await service.loadConversation('chat')).single.text, 'pending');
        await Future.wait(
          List.generate(
            20,
            (i) => service.saveImmediately('chat', [message('$i')]),
          ),
        );
        expect((await service.loadConversation('chat')).single.text, '19');
        final writing = service.saveImmediately('chat', [message('last')]);
        final deleting = service.deleteConversation('chat');
        await Future.wait([writing, deleting]);
        expect(await service.loadConversation('chat'), isEmpty);
        final blockedTemp = Directory('${dir.path}\\chat.json.tmp');
        await blockedTemp.create();
        await service.saveImmediately('chat', [message('retry')]);
        await expectLater(service.flush(), throwsA(isA<FileSystemException>()));
        await blockedTemp.delete();
        await service.flush();
        expect((await service.loadConversation('chat')).single.text, 'retry');
      } finally {
        await service.flush();
        service.setCustomDirectoryForTesting(null);
        AppPreferences().setCustomFileForTesting(null);
        await dir.delete(recursive: true);
      }
    },
  );
}
