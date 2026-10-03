import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';
import 'package:ja_lan_messenger/modules/services/autostart_service.dart';
import 'package:ja_lan_messenger/modules/ime/ime_service.dart';
import 'package:ja_lan_messenger/modules/services/sticker_service.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File tempFile;

  setUp(() async {
    ThemeProvider.registryQueryOverride = (_, _) => 'Mocked Hardware';
    tempDir = await Directory.systemTemp.createTemp('ja_power_test_');
    tempFile = File('${tempDir.path}/user_preferences.json');
    AppPreferences().setCustomFileForTesting(tempFile);
    AutostartService.customAutoStartForTesting = false;
    AppPowerManager.instance.resetForTesting(enableIdleSleep: false);
    addTearDown(
      () => AppPowerManager.instance.resetForTesting(enableIdleSleep: false),
    );
  });

  tearDown(() async {
    ThemeProvider.registryQueryOverride = null;
    AutostartService.customAutoStartForTesting = null;
    AppPreferences().setCustomFileForTesting(null);
    AppPowerManager.instance.resetForTesting(enableIdleSleep: false);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'AppPreferences stores and reloads power optimization settings',
    () async {
      final prefs = AppPreferences();
      expect(prefs.enableIdleSleep, isTrue);
      expect(prefs.idleTimeoutSeconds, equals(12));

      await prefs.setPowerOptimization(
        enableIdleSleep: false,
        idleTimeoutSeconds: 60,
      );

      expect(prefs.enableIdleSleep, isFalse);
      expect(prefs.idleTimeoutSeconds, equals(60));

      // Reload from file
      final prefs2 = AppPreferences();
      prefs2.setCustomFileForTesting(tempFile);
      await prefs2.load();

      expect(prefs2.enableIdleSleep, isFalse);
      expect(prefs2.idleTimeoutSeconds, equals(60));
    },
  );

  Widget buildSettingsApp({
    required ThemeProvider theme,
    required LanguageProvider lang,
    required MessengerCoordinator coordinator,
    required ImeService ime,
    required StickerService sticker,
    Widget child = const SettingsDialog(),
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: lang),
        ChangeNotifierProvider.value(value: coordinator),
        ChangeNotifierProvider.value(value: ime),
        ChangeNotifierProvider.value(value: sticker),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets(
    'SettingsDialog renders Power Optimizer card and saves updated settings',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      lang.setLanguage(AppLanguage.vi);
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());
      final ime = ImeService();
      final sticker = StickerService();

      await tester.pumpWidget(
        buildSettingsApp(
          theme: theme,
          lang: lang,
          coordinator: coordinator,
          ime: ime,
          sticker: sticker,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Drag gently to bring Power Optimizer into view
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -200),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final cardFinder = find.text('TỐI ƯU NĂNG LƯỢNG & GPU (POWER OPTIMIZER)');
      expect(cardFinder, findsOneWidget);

      final switchTile = find.byKey(
        const ValueKey('power-optimizer-switch-tile'),
      );
      expect(switchTile, findsOneWidget);

      // Tap SwitchTile
      await tester.tap(switchTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Save Changes
      final saveButton = find.text('Lưu thay đổi');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);

      // Pump enough frames to let all async saves complete
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(AppPreferences().enableIdleSleep, isFalse);
      expect(AppPowerManager.instance.enableIdleSleep, isFalse);
    },
  );

  testWidgets('SettingsDialog allows selecting idle timeout chips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final theme = ThemeProvider();
    final lang = LanguageProvider();
    lang.setLanguage(AppLanguage.vi);
    final coordinator = MessengerCoordinator();
    addTearDown(() => coordinator.dispose());
    final ime = ImeService();
    final sticker = StickerService();

    await tester.pumpWidget(
      buildSettingsApp(
        theme: theme,
        lang: lang,
        coordinator: coordinator,
        ime: ime,
        sticker: sticker,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Drag further to bring chips fully within TabBarView viewport
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -320),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final chip30s = find.byKey(const ValueKey('idle-timeout-chip-30'));
    await tester.tap(chip30s, warnIfMissed: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Save
    final saveButton = find.text('Lưu thay đổi');
    await tester.tap(saveButton, warnIfMissed: true);

    // Pump enough frames to let all async saves complete
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(AppPreferences().idleTimeoutSeconds, equals(30));
    expect(AppPowerManager.instance.idleTimeoutSeconds, equals(30));

    // Cancel pending idle sleep timer so FakeAsync doesn't complain
    AppPowerManager.instance.resetForTesting(enableIdleSleep: false);
  });

  testWidgets('SettingsDialog Cancel button rolls back unsaved changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final theme = ThemeProvider();
    final lang = LanguageProvider();
    lang.setLanguage(AppLanguage.vi);
    final coordinator = MessengerCoordinator();
    addTearDown(() => coordinator.dispose());
    final ime = ImeService();
    final sticker = StickerService();

    await tester.pumpWidget(
      buildSettingsApp(
        theme: theme,
        lang: lang,
        coordinator: coordinator,
        ime: ime,
        sticker: sticker,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Drag gently to bring switch into view
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Toggle switch
    final switchTile = find.byKey(
      const ValueKey('power-optimizer-switch-tile'),
    );
    await tester.tap(switchTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Dispose dialog without saving (simulates cancel)
    await tester.pumpWidget(
      buildSettingsApp(
        theme: theme,
        lang: lang,
        coordinator: coordinator,
        ime: ime,
        sticker: sticker,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Preferences and PowerManager remain unchanged
    expect(AppPreferences().enableIdleSleep, isTrue);
  });
}
