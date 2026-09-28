import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';

void main() {
  testWidgets(
    'return follows newest only when conversation was left at bottom',
    (tester) async {
      late MessengerCoordinator c;
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('scroll_restore_');
        AppPreferences().setCustomFileForTesting(
          File('${dir.path}/prefs.json'),
        );
        await AppPreferences().load();
        ChatHistoryService().setCustomDirectoryForTesting(
          Directory('${dir.path}/history')..createSync(),
        );
        MessengerCoordinator.customGroupsFileForTesting = File(
          '${dir.path}/groups.json',
        );
        c = MessengerCoordinator(
          knownDevices: KnownDevicesRegistry('${dir.path}/devices.json'),
        );
        await c.historyLoaded;
      });
      final theme = ThemeProvider();
      final lang = LanguageProvider();
      addTearDown(() {
        c.dispose();
        theme.dispose();
        lang.dispose();
        ChatHistoryService().setCustomDirectoryForTesting(null);
        AppPreferences().setCustomFileForTesting(null);
        MessengerCoordinator.customGroupsFileForTesting = null;
      });
      final a = PeerModel(id: 'A', name: 'A', ip: '192.0.2.1');
      final b = PeerModel(id: 'B', name: 'B', ip: '192.0.2.2');
      c.peersMap[a.id] = a;
      c.peersMap[b.id] = b;
      MessageModel message(int i, {bool read = true}) => MessageModel(
        id: '$i',
        senderId: a.id,
        senderName: 'A',
        recipientId: 'me',
        text: 'Message $i with enough text to fill the conversation history.',
        isMine: false,
        status: read ? MessageStatus.read : MessageStatus.delivered,
      );
      final history = List.generate(60, (i) => message(i));
      c.conversationsMap[a.id] = history;
      c.conversationsMap[b.id] = [];
      c.selectPeer(a);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: c),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
        ),
      );
      await tester.pumpAndSettle();
      ScrollController controller() =>
          tester.widget<ListView>(find.byType(ListView).first).controller!;
      expect(controller().position.extentAfter, lessThan(3));
      c.selectPeer(b);
      await tester.pumpAndSettle();
      history.addAll(List.generate(25, (i) => message(60 + i, read: false)));
      c.selectPeer(a);
      await tester.pumpAndSettle();
      expect(controller().position.extentAfter, lessThan(3));
      expect(
        history.last.status,
        MessageStatus.delivered,
      ); // No native focus proof.

      controller().jumpTo(350);
      await tester.pumpAndSettle();
      final oldOffset = controller().offset;
      c.selectPeer(b);
      await tester.pumpAndSettle();
      history.addAll(List.generate(10, (i) => message(100 + i, read: false)));
      c.selectPeer(a);
      await tester.pumpAndSettle();
      expect(controller().offset, closeTo(oldOffset, 1));
      expect(controller().position.extentAfter, greaterThan(100));
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expect(history.last.status, MessageStatus.delivered);
      await tester.pumpWidget(const SizedBox());
      c.chatHistory.cancelAll();
    },
  );
}
