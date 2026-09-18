import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_dialog.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/settings_dialog.dart';

void main() {
  late Directory tempDir;
  late File tempFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ja_glass_test_');
    tempFile = File('${tempDir.path}/user_preferences.json');
    AppPreferences().setCustomFileForTesting(tempFile);
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppPreferences Glass Tuning Persistence', () {
    test('defaults to null values', () {
      final prefs = AppPreferences();
      expect(prefs.cardBlur, isNull);
      expect(prefs.cardOpacity, isNull);
      expect(prefs.dialogBlur, isNull);
      expect(prefs.dialogOpacity, isNull);
    });

    test('persists custom glass tuning parameters across instances', () async {
      final prefs1 = AppPreferences();
      await prefs1.setGlassTuning(
        cardBlur: 14.5,
        cardOpacity: 0.38,
        dialogBlur: 12.0,
        dialogOpacity: 0.82,
      );

      expect(prefs1.cardBlur, 14.5);
      expect(prefs1.cardOpacity, 0.38);
      expect(prefs1.dialogBlur, 12.0);
      expect(prefs1.dialogOpacity, 0.82);
      expect(await tempFile.exists(), isTrue);

      final prefs2 = AppPreferences();
      prefs2.setCustomFileForTesting(tempFile);
      await prefs2.load();

      expect(prefs2.cardBlur, 14.5);
      expect(prefs2.cardOpacity, 0.38);
      expect(prefs2.dialogBlur, 12.0);
      expect(prefs2.dialogOpacity, 0.82);
    });

    test('resetToDefaults resets glass parameters to null', () async {
      final prefs = AppPreferences();
      await prefs.setGlassTuning(cardBlur: 10.0, cardOpacity: 0.50);
      expect(prefs.cardBlur, 10.0);

      prefs.resetToDefaults();
      expect(prefs.cardBlur, isNull);
      expect(prefs.cardOpacity, isNull);
      expect(prefs.dialogBlur, isNull);
      expect(prefs.dialogOpacity, isNull);
    });
  });

  group('ThemeProvider Glass Tuning & Theme Modes', () {
    test('has expected default glass parameters', () {
      final theme = ThemeProvider();
      expect(theme.cardBlur, 24.0);
      expect(theme.cardOpacity, 0.28);
      expect(theme.dialogBlur, 20.0);
      expect(theme.dialogOpacity, 0.88);
    });

    test(
      'setLiveGlassmorphism updates values and notifies listeners without saving',
      () {
        final theme = ThemeProvider();
        int notifyCount = 0;
        theme.addListener(() => notifyCount++);

        theme.setLiveGlassmorphism(
          cardBlur: 30.0,
          cardOpacity: 0.40,
          dialogBlur: 15.0,
          dialogOpacity: 0.70,
        );

        expect(theme.cardBlur, 30.0);
        expect(theme.cardOpacity, 0.40);
        expect(theme.dialogBlur, 15.0);
        expect(theme.dialogOpacity, 0.70);
        expect(notifyCount, 1);
        // AppPreferences was not updated
        expect(AppPreferences().cardBlur, isNull);
      },
    );

    test(
      'saveGlassTuning updates values, notifies, and persists to AppPreferences',
      () async {
        final theme = ThemeProvider();
        int notifyCount = 0;
        theme.addListener(() => notifyCount++);

        await theme.saveGlassTuning(
          cardBlur: 18.0,
          cardOpacity: 0.32,
          dialogBlur: 22.0,
          dialogOpacity: 0.90,
        );

        expect(theme.cardBlur, 18.0);
        expect(theme.cardOpacity, 0.32);
        expect(theme.dialogBlur, 22.0);
        expect(theme.dialogOpacity, 0.90);
        expect(notifyCount, 1);
        expect(AppPreferences().cardBlur, 18.0);
        expect(AppPreferences().cardOpacity, 0.32);
        expect(AppPreferences().dialogBlur, 22.0);
        expect(AppPreferences().dialogOpacity, 0.90);
      },
    );

    test(
      'preserves glass tuning parameters across dark and light mode toggle',
      () {
        final theme = ThemeProvider();
        theme.setLiveGlassmorphism(
          cardBlur: 28.0,
          cardOpacity: 0.35,
          dialogBlur: 18.0,
          dialogOpacity: 0.75,
        );

        theme.setThemeMode('light');
        expect(theme.isDark, isFalse);
        expect(theme.cardBlur, 28.0);
        expect(theme.cardOpacity, 0.35);

        theme.setThemeMode('dark');
        expect(theme.isDark, isTrue);
        expect(theme.cardBlur, 28.0);
        expect(theme.cardOpacity, 0.35);
      },
    );
  });

  group('GlassDialog Widget Blur & Opacity Behavior', () {
    testWidgets(
      'renders BackdropFilter with theme.dialogBlur when blurSigma is null',
      (tester) async {
        final theme = ThemeProvider();
        theme.setLiveGlassmorphism(dialogBlur: 25.0, dialogOpacity: 0.85);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: GlassDialog(
                  title: 'Test Dialog',
                  child: Text('Dialog Content'),
                ),
              ),
            ),
          ),
        );

        final backdropFilterFinder = find.byType(BackdropFilter);
        expect(backdropFilterFinder, findsOneWidget);
        final backdropWidget = tester.widget<BackdropFilter>(
          backdropFilterFinder,
        );
        expect(
          backdropWidget.filter,
          ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
        );
      },
    );

    testWidgets('omits BackdropFilter when dialogBlur is 0', (tester) async {
      final theme = ThemeProvider();
      theme.setLiveGlassmorphism(dialogBlur: 0.0);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: GlassDialog(
                title: 'No Blur Dialog',
                blurSigma: 0.0,
                child: Text('Content'),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('No Blur Dialog'), findsOneWidget);
    });

    testWidgets('responds to live glassmorphism tuning updates', (
      tester,
    ) async {
      final theme = ThemeProvider();
      theme.setLiveGlassmorphism(dialogBlur: 10.0);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: GlassDialog(
                title: 'Live Tuning Dialog',
                child: Text('Content'),
              ),
            ),
          ),
        ),
      );

      var backdropWidget = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(
        backdropWidget.filter,
        ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
      );

      // Dynamically update blur
      theme.setLiveGlassmorphism(dialogBlur: 32.0);
      await tester.pump();

      backdropWidget = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(
        backdropWidget.filter,
        ImageFilter.blur(sigmaX: 32.0, sigmaY: 32.0),
      );
    });
  });

  group('SettingsDialog Live Preview and Revert Behavior', () {
    testWidgets('reverts glass tuning when closed without saving', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final theme = ThemeProvider();
      theme.setLiveGlassmorphism(cardBlur: 20.0, cardOpacity: 0.30);
      final coordinator = MessengerCoordinator();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsDialog())),
        ),
      );

      // Verify initial values
      expect(theme.cardBlur, 20.0);

      // Simulate live change during preview
      theme.setLiveGlassmorphism(cardBlur: 35.0);
      expect(theme.cardBlur, 35.0);

      // Dispose the dialog by pumping an empty widget (simulating close/cancel)
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );

      // Verify values reverted back to initial state after microtask executes
      await tester.pump();
      expect(theme.cardBlur, 20.0);

      coordinator.dispose();
      await tester.pumpAndSettle();
    });
  });
}
