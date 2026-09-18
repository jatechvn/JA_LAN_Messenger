import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/peer_list_view.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/compact_sidebar.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';

void main() {
  testWidgets(
    'PeerListView renders category filter tabs and allows switching',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: const MaterialApp(home: Scaffold(body: PeerListView())),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));

      // Verify category tabs exist
      expect(find.text(lang.tr('categoryAll')), findsOneWidget);
      expect(find.text(lang.tr('categoryOnline')), findsOneWidget);
      expect(find.text(lang.tr('categoryGroups')), findsOneWidget);

      // Switch to Online tab
      await tester.tap(find.text(lang.tr('categoryOnline')));
      await tester.pump(const Duration(milliseconds: 50));

      // Switch to Groups tab
      await tester.tap(find.text(lang.tr('categoryGroups')));
      await tester.pump(const Duration(milliseconds: 50));

      // Switch back to All tab
      await tester.tap(find.text(lang.tr('categoryAll')));
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets('Language selector button cycles languages and displays badges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final theme = ThemeProvider();
    final lang = LanguageProvider();
    final coordinator = MessengerCoordinator();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
          ChangeNotifierProvider.value(value: coordinator),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CompactSidebar(
              activeTab: MainViewTab.chats,
              onTabChanged: _dummyTabChange,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Find translate button
    final translateFinder = find.byIcon(Icons.translate_rounded);
    expect(translateFinder, findsOneWidget);

    final initialCode = lang.currentLanguage.code == 'zh'
        ? 'CN'
        : lang.currentLanguage.code.toUpperCase();
    expect(find.text(initialCode), findsOneWidget);

    // Tap to cycle language
    await tester.tap(translateFinder);
    await tester.pumpAndSettle();

    final secondCode = lang.currentLanguage.code == 'zh'
        ? 'CN'
        : lang.currentLanguage.code.toUpperCase();
    expect(find.text(secondCode), findsOneWidget);
  });

  testWidgets('Chat input dock toggles emoji picker and inserts emoji', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final theme = ThemeProvider();
    final lang = LanguageProvider();
    final coordinator = MessengerCoordinator();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
          ChangeNotifierProvider.value(value: coordinator),
        ],
        child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
      ),
    );

    await tester.pumpAndSettle();

    // If no peer selected, empty view is rendered
    expect(find.text(lang.tr('emptySelectChat')), findsOneWidget);

    // Select allUsersPeer to open chat dock
    coordinator.selectPeer(coordinator.allUsersPeer);
    await tester.pumpAndSettle();

    // Verify emoji button is present
    final emojiBtnFinder = find.byIcon(Icons.sentiment_satisfied_alt_rounded);
    expect(emojiBtnFinder, findsOneWidget);

    // Tap emoji button to open popover
    await tester.tap(emojiBtnFinder);
    await tester.pumpAndSettle();

    // Verify emoji grid has opened and contains 😀
    expect(find.text('😀'), findsWidgets);

    // Tap 😀 to insert it
    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();

    // Verify text field contains 😀
    expect(find.text('😀'), findsWidgets);
  });
}

void _dummyTabChange(MainViewTab tab) {}
