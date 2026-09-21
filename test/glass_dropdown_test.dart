import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_dropdown.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/compact_sidebar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('glass_dropdown_test_');
    AppPreferences().setCustomFileForTesting(
      File('${tempDir.path}${Platform.pathSeparator}prefs.json'),
    );
    await AppPreferences().load();
    ThemeProvider.registryQueryOverride = null;
  });

  tearDown(() async {
    ThemeProvider.registryQueryOverride = null;
    AppPreferences().setCustomFileForTesting(null);
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('GlassDropdown Standalone Widget Tests', () {
    testWidgets('Renders custom trigger and opens frosted menu upon click', (
      tester,
    ) async {
      String? selectedValue = 'online';
      final theme = ThemeProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Center(
                    child: GlassDropdown<String>(
                      items: const [
                        GlassDropdownItem<String>(
                          value: 'online',
                          label: 'Online',
                          icon: Icons.check_circle_rounded,
                        ),
                        GlassDropdownItem<String>(
                          value: 'away',
                          label: 'Away',
                          icon: Icons.schedule_rounded,
                        ),
                        GlassDropdownItem<String>(
                          value: 'busy',
                          label: 'Busy',
                          icon: Icons.do_not_disturb_on_rounded,
                        ),
                      ],
                      value: selectedValue,
                      onChanged: (val) {
                        setState(() => selectedValue = val);
                      },
                      customTrigger: const Text('Status Trigger Button'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Initially, menu is not visible
      expect(find.text('Status Trigger Button'), findsOneWidget);
      expect(find.text('Away'), findsNothing);

      // Tap trigger to open dropdown
      await tester.tap(find.text('Status Trigger Button'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Menu is now visible with frosted glass items
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Away'), findsOneWidget);
      expect(find.text('Busy'), findsOneWidget);

      // Tap 'Away' item
      await tester.tap(find.text('Away'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Value updated and dropdown closed
      expect(selectedValue, equals('away'));
      expect(find.text('Away'), findsNothing);
    });

    testWidgets('Tapping barrier outside closes dropdown', (tester) async {
      final theme = ThemeProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: GlassDropdown<String>(
                  items: const [
                    GlassDropdownItem<String>(value: '1', label: 'Item 1'),
                    GlassDropdownItem<String>(value: '2', label: 'Item 2'),
                  ],
                  value: '1',
                  onChanged: (_) {},
                  customTrigger: const Text('Open Menu'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Item 2'), findsOneWidget);

      // Tap far outside at top-left corner
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Item 2'), findsNothing);
    });

    testWidgets('Pressing Escape key closes dropdown', (tester) async {
      final theme = ThemeProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: GlassDropdown<String>(
                  items: const [
                    GlassDropdownItem<String>(value: '1', label: 'Item 1'),
                    GlassDropdownItem<String>(value: '2', label: 'Item 2'),
                  ],
                  value: '1',
                  onChanged: (_) {},
                  customTrigger: const Text('Open Menu'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Item 2'), findsOneWidget);

      // Send escape key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Item 2'), findsNothing);
    });
  });

  group('CompactSidebar Status GlassDropdown Integration', () {
    testWidgets(
      'CompactSidebar avatar opens status GlassDropdown and selects Away',
      (tester) async {
        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<LanguageProvider>.value(value: lang),
              ChangeNotifierProvider<MessengerCoordinator>.value(
                value: coordinator,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: CompactSidebar(
                  activeTab: MainViewTab.chats,
                  onTabChanged: (_) {},
                ),
              ),
            ),
          ),
        );

        // Find status avatar at the bottom
        expect(find.byType(GlassDropdown<PeerStatus>), findsOneWidget);

        // Tap the avatar
        await tester.tap(find.byType(GlassDropdown<PeerStatus>));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Check that status options are displayed with proper text
        expect(find.text('Online'), findsOneWidget);
        expect(find.text('Away'), findsOneWidget);
        expect(find.text('Busy'), findsOneWidget);

        // Tap 'Away'
        await tester.tap(find.text('Away'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify coordinator local status changed to away
        expect(coordinator.localStatus, equals(PeerStatus.away));
      },
    );
  });
}
