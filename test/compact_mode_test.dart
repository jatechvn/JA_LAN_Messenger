import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/constants.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/main_messenger_window.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/compact_messenger_view.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File prefFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('compact_test_');
    prefFile = File('${tempDir.path}/user_preferences.json');
    AppPreferences().setCustomFileForTesting(prefFile);
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Compact Mode Constants & Localization Tests', () {
    test(
      'Compact restoration rejects standard geometry and keeps valid sizes',
      () {
        expect(restoredCompactWidth(1280), 340);
        expect(restoredCompactHeight(1280, 720), 560);
        expect(restoredCompactWidth(350), 350);
        expect(restoredCompactHeight(350, 570), 570);
        expect(restoredCompactWidth(200), 320);
        expect(restoredCompactHeight(350, 300), 420);
        expect(restoredCompactWidth(null), 340);
      },
    );
    test('Compact window constants are properly defined', () {
      expect(defaultCompactWidth, equals(340.0));
      expect(defaultCompactHeight, equals(560.0));
      expect(minCompactWidth, equals(320.0));
      expect(minCompactHeight, equals(420.0));
    });

    test('Localization keys for compact mode exist in vi, en, zh', () {
      final lang = LanguageProvider();

      for (final locale in AppLanguage.values) {
        lang.setLanguage(locale);
        expect(lang.tr('compactMode'), isNotEmpty);
        expect(lang.tr('standardMode'), isNotEmpty);
        expect(lang.tr('alwaysOnTop'), isNotEmpty);
        expect(lang.tr('unpinFromTop'), isNotEmpty);
        expect(lang.tr('backToChats'), isNotEmpty);
        expect(lang.tr('allFilter'), isNotEmpty);
        expect(lang.tr('unreadFilter'), isNotEmpty);
        expect(lang.tr('onlineFilter'), isNotEmpty);
      }
    });
  });

  group('AppPreferences Compact & Geometry Persistence Tests', () {
    test(
      'Default values and setters for compact mode and always on top',
      () async {
        final prefs = AppPreferences();
        expect(prefs.isCompactMode, isFalse);
        expect(prefs.isAlwaysOnTop, isFalse);

        await prefs.setCompactMode(true);
        await prefs.setAlwaysOnTop(true);
        expect(prefs.isCompactMode, isTrue);
        expect(prefs.isAlwaysOnTop, isTrue);

        await prefs.saveCompactGeometry(
          width: 350.0,
          height: 570.0,
          x: 800.0,
          y: 400.0,
        );
        expect(prefs.compactWidth, equals(350.0));
        expect(prefs.compactHeight, equals(570.0));
        expect(prefs.compactPosX, equals(800.0));
        expect(prefs.compactPosY, equals(400.0));

        await prefs.saveNormalGeometry(
          width: 1000.0,
          height: 700.0,
          x: 100.0,
          y: 100.0,
        );
        expect(prefs.normalWidth, equals(1000.0));
        expect(prefs.normalHeight, equals(700.0));
        expect(prefs.normalPosX, equals(100.0));
        expect(prefs.normalPosY, equals(100.0));

        // Test reload from disk
        final newPrefs = AppPreferences();
        await newPrefs.load();
        expect(newPrefs.isCompactMode, isTrue);
        expect(newPrefs.isAlwaysOnTop, isTrue);
        expect(newPrefs.compactWidth, equals(350.0));
        expect(newPrefs.normalWidth, equals(1000.0));
      },
    );
  });

  group('MessengerCoordinator Compact Mode Logic Tests', () {
    test('Coordinator toggles compact mode and always on top', () async {
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      expect(coordinator.isCompactMode, isFalse);
      expect(coordinator.isAlwaysOnTop, isFalse);

      coordinator.setCompactModeForTesting(true);
      expect(coordinator.isCompactMode, isTrue);

      coordinator.setAlwaysOnTopForTesting(true);
      expect(coordinator.isAlwaysOnTop, isTrue);

      await coordinator.toggleAlwaysOnTop();
      expect(coordinator.isAlwaysOnTop, isFalse);
    });
  });

  group('CompactMessengerView UI Widget Tests', () {
    testWidgets(
      'Renders conversation list, filters and search when no peer selected',
      (tester) async {
        tester.view.physicalSize = const Size(340, 560);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peerA = PeerModel(
          id: 'peer_a',
          name: 'Alice',
          ip: '192.168.1.10',
          status: PeerStatus.online,
          unreadCount: 3,
          lastMessage: 'Hello Alice here',
        );
        final peerB = PeerModel(
          id: 'peer_b',
          name: 'Bob',
          ip: '192.168.1.20',
          status: PeerStatus.offline,
          unreadCount: 0,
          lastMessage: 'See you tomorrow',
        );

        coordinator.peersMap[peerA.id] = peerA;
        coordinator.peersMap[peerB.id] = peerB;
        coordinator.selectPeer(null);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
              ChangeNotifierProvider.value(value: coordinator),
            ],
            child: const MaterialApp(
              home: Scaffold(body: CompactMessengerView()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Top bar contains app title and always on top button
        expect(find.text(appName), findsOneWidget);
        final titleRender = tester.renderObject<RenderParagraph>(find.text(appName));
        // Verify that appName receives full available width (> 140px in 340px window)
        // instead of being cut in half by a competing Spacer widget
        expect(
          titleRender.constraints.maxWidth,
          greaterThan(140.0),
          reason: 'App name should receive all available width in compact mode',
        );
        expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
        expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);

        // Search box and filter pills
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text(lang.tr('allFilter')), findsOneWidget);
        expect(find.text(lang.tr('unreadFilter')), findsOneWidget);
        expect(find.text(lang.tr('onlineFilter')), findsOneWidget);

        // Alice with badge 3 is present
        expect(find.text('Alice'), findsOneWidget);
        expect(
          find.descendant(of: find.byType(ListView), matching: find.text('3')),
          findsOneWidget,
        );
        expect(find.text('Hello Alice here'), findsOneWidget);

        // Tap on Alice selects Alice and transitions to ChatViewPanel
        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        expect(coordinator.selectedPeer?.id, equals(peerA.id));
        expect(find.byType(ChatViewPanel), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

        // Tap on back arrow returns to conversation list
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        expect(coordinator.selectedPeer, isNull);
        expect(find.text(appName), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
      },
    );

    testWidgets('Filter pills correctly filter peers', (tester) async {
      tester.view.physicalSize = const Size(340, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      final peerA = PeerModel(
        id: 'peer_a',
        name: 'Alice',
        ip: '192.168.1.10',
        status: PeerStatus.online,
        unreadCount: 2,
      );
      final peerB = PeerModel(
        id: 'peer_b',
        name: 'Bob',
        ip: '192.168.1.20',
        status: PeerStatus.offline,
        unreadCount: 0,
      );

      coordinator.peersMap[peerA.id] = peerA;
      coordinator.peersMap[peerB.id] = peerB;
      coordinator.selectPeer(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CompactMessengerView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In All filter, both Alice and Bob are displayed
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Tap on Unread filter: Alice has 2 unread, Bob has 0
      await tester.tap(find.text(lang.tr('unreadFilter')));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);

      // Tap on Online filter: Alice is online, Bob is offline
      await tester.tap(find.text(lang.tr('onlineFilter')));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });
  });

  group('MainMessengerWindow Compact Mode Integration Tests', () {
    testWidgets(
      'Toggling compact mode switches between 3-column and compact layout',
      (tester) async {
        tester.view.physicalSize = const Size(960, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        theme.setPerfTierMode(PerfTierMode.lite);
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        coordinator.setCompactModeForTesting(false);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
              ChangeNotifierProvider.value(value: coordinator),
            ],
            child: const MaterialApp(home: MainMessengerWindow()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Standard mode has the PiP / compact button in title bar
        expect(
          find.byIcon(Icons.picture_in_picture_alt_rounded),
          findsOneWidget,
        );
        expect(find.byType(CompactMessengerView), findsNothing);

        // The mode control stays at the trailing edge at every standard width.
        for (final width in [720.0, 960.0, 1266.0]) {
          tester.view.physicalSize = Size(width, 640);
          await tester.pump();
          final control = tester.getRect(
            find.byTooltip(lang.tr('compactMode')),
          );
          expect(control.right, closeTo(width - 14, 1));
          expect(tester.takeException(), isNull);
        }

        // Tap compact button
        coordinator.setCompactModeForTesting(true);
        tester.view.physicalSize = const Size(320, 560);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Now compact view is active
        expect(find.byType(CompactMessengerView), findsOneWidget);
        expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Tap expand to standard mode
        tester.view.physicalSize = const Size(960, 640);
        coordinator.setCompactModeForTesting(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CompactMessengerView), findsNothing);
        expect(
          find.byIcon(Icons.picture_in_picture_alt_rounded),
          findsOneWidget,
        );
      },
    );
  });
}
