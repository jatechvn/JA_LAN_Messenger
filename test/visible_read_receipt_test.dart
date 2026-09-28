import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'read requires focused visible window, dwell, unobscured viewport',
    (tester) async {
      late MessengerCoordinator c;
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('visible_read_');
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
      var focused = false;
      var visible = true;
      var minimized = false;
      const channel = MethodChannel('window_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'isFocused':
                return focused;
              case 'isVisible':
                return visible;
              case 'isMinimized':
                return minimized;
              default:
                return null;
            }
          });
      final theme = ThemeProvider();
      final lang = LanguageProvider();
      addTearDown(() async {
        c.chatHistory.cancelAll();
        c.dispose();
        theme.dispose();
        lang.dispose();
        ChatHistoryService().setCustomDirectoryForTesting(null);
        AppPreferences().setCustomFileForTesting(null);
        MessengerCoordinator.customGroupsFileForTesting = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final peer = c.allUsersPeer;
      MessageModel message(String id) => MessageModel(
        id: id,
        senderId: 'remote',
        senderName: 'Remote',
        recipientId: peer.id,
        text: 'Visible message $id',
        isMine: false,
        status: MessageStatus.delivered,
      );
      final first = message('1');
      c.conversationsMap[peer.id] = [first];
      peer.unreadCount = 1;
      c.selectPeer(peer);
      expect(first.status, MessageStatus.delivered);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: c),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: ChatViewPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> dwell() async {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
      }

      await dwell();
      expect(first.status, MessageStatus.delivered);
      focused = true;
      visible = false;
      await dwell();
      expect(first.status, MessageStatus.delivered);
      visible = true;
      minimized = true;
      await dwell();
      expect(first.status, MessageStatus.delivered);
      minimized = false;
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Cover chat')),
      );
      await tester.pumpAndSettle();
      await dwell();
      expect(first.status, MessageStatus.delivered);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(first.status, MessageStatus.delivered);
      await dwell();
      expect(first.status, MessageStatus.read);
      expect(peer.unreadCount, 0);
      // Offscreen new messages must stay unread while the user reads history.
      final history = List.generate(
        70,
        (i) => message('${100 + i}')..status = MessageStatus.read,
      );
      c.conversationsMap[peer.id] = history;
      c.notifyListeners();
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<ListView>(find.byType(ListView).first)
          .controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      final newest = message('999');
      history.add(newest);
      c.notifyListeners();
      await tester.pumpAndSettle();
      await dwell();
      expect(newest.status, MessageStatus.delivered);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await dwell();
      expect(newest.status, MessageStatus.read);
      await tester.pumpWidget(const SizedBox());
      c.chatHistory.cancelAll();
      expect(tester.takeException(), isNull);
    },
  );
}
