import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/services/sticker_service.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/sticker_picker_popover.dart';

void main() {
  testWidgets(
    'selecting sticker closes picker, sends once and preserves draft',
    (tester) async {
      late MessengerCoordinator coordinator;
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('sticker_close_');
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
        coordinator = MessengerCoordinator(
          knownDevices: KnownDevicesRegistry('${dir.path}/devices.json'),
        );
        await coordinator.historyLoaded;
      });
      final theme = ThemeProvider();
      final lang = LanguageProvider();
      addTearDown(() {
        coordinator.dispose();
        theme.dispose();
        lang.dispose();
        ChatHistoryService().setCustomDirectoryForTesting(null);
        AppPreferences().setCustomFileForTesting(null);
        MessengerCoordinator.customGroupsFileForTesting = null;
      });
      coordinator.selectPeer(coordinator.allUsersPeer);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: coordinator),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: StickerService()),
          ],
          child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Draft to keep');
      await tester.tap(find.byIcon(Icons.sticky_note_2_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPickerPopover), findsOneWidget);
      // Exercise the same selection callback used by a sticker tile.
      await tester.runAsync(() async {
        tester
            .widget<StickerPickerPopover>(find.byType(StickerPickerPopover))
            .onSelectSticker(
              const StickerItem(
                id: '1',
                packId: 'test',
                previewPath: '',
                spritePath: '',
              ),
            );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.byType(StickerPickerPopover), findsNothing);
      expect(find.text('Draft to keep'), findsOneWidget);
      expect(
        coordinator.currentMessages.where((m) => m.text == '[sticker:test/1]'),
        hasLength(1),
      );
      await tester.tap(find.byIcon(Icons.sticky_note_2_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPickerPopover), findsOneWidget);
      // Clicking inside keeps the picker; the trigger still toggles it closed.
      await tester.tapAt(tester.getCenter(find.byType(StickerPickerPopover)));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPickerPopover), findsOneWidget);
      await tester.tap(find.byTooltip(lang.tr('stickers')));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPickerPopover), findsNothing);
      await tester.tap(find.byTooltip(lang.tr('stickers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(find.byType(StickerPickerPopover), findsNothing);
      expect(find.text('Draft to keep'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.sentiment_satisfied_alt_rounded));
      await tester.pumpAndSettle();
      expect(find.text(lang.tr('emojis')), findsOneWidget);
      await tester.tap(find.text(lang.tr('emojis')));
      await tester.pumpAndSettle();
      expect(find.text(lang.tr('emojis')), findsOneWidget);
      // Switching directly to stickers must not reopen the old picker.
      await tester.tap(find.byTooltip(lang.tr('stickers')));
      await tester.pumpAndSettle();
      expect(find.text(lang.tr('emojis')), findsNothing);
      expect(find.byType(StickerPickerPopover), findsOneWidget);
      await tester.tap(find.byIcon(Icons.sentiment_satisfied_alt_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPickerPopover), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text(lang.tr('emojis')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      coordinator.chatHistory.cancelAll();
    },
  );
}
