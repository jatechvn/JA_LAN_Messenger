import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/theme/styles_win10.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_components.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('perf_tier_test_');
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

  group('Hardware Score & Tier Calculation Tests', () {
    test(
      'Intel N100 Mini PC is accurately classified as HardwareTier.lite',
      () {
        final score = ThemeProvider.calculateHardwareScore(
          cpu: 'Intel(R) N100',
          gpu: 'Intel(R) UHD Graphics',
          cores: 4,
          isWin11: false,
        );

        expect(score, lessThan(45));
        final tier = ThemeProvider.calculateTierFromScore(score);
        expect(tier, equals(HardwareTier.lite));
      },
    );

    test(
      'Celeron J4125 / N4020 Mini PC is classified as HardwareTier.lite',
      () {
        final score = ThemeProvider.calculateHardwareScore(
          cpu: 'Intel(R) Celeron(R) J4125 CPU @ 2.00GHz',
          gpu: 'Intel(R) UHD Graphics 600',
          cores: 4,
          isWin11: false,
        );

        expect(score, lessThan(45));
        final tier = ThemeProvider.calculateTierFromScore(score);
        expect(tier, equals(HardwareTier.lite));
      },
    );

    test(
      'Mid-range PC (i5-8400, 6 cores) is classified as HardwareTier.balanced',
      () {
        final score = ThemeProvider.calculateHardwareScore(
          cpu: 'Intel(R) Core(TM) i5-8400 CPU @ 2.80GHz',
          gpu: 'Intel(R) UHD Graphics 630',
          cores: 6,
          isWin11: false,
        );

        expect(score, greaterThanOrEqualTo(45));
        expect(score, lessThan(75));
        final tier = ThemeProvider.calculateTierFromScore(score);
        expect(tier, equals(HardwareTier.balanced));
      },
    );

    test(
      'High-end workstation (i7-13700, 16 cores, UHD 770) is HardwareTier.ultra',
      () {
        final score = ThemeProvider.calculateHardwareScore(
          cpu: '13th Gen Intel(R) Core(TM) i7-13700',
          gpu: 'Intel(R) UHD Graphics 770',
          cores: 16,
          isWin11: true,
        );

        expect(score, greaterThanOrEqualTo(75));
        final tier = ThemeProvider.calculateTierFromScore(score);
        expect(tier, equals(HardwareTier.ultra));
      },
    );

    test('Gaming PC with discrete NVIDIA RTX GPU is HardwareTier.ultra', () {
      final score = ThemeProvider.calculateHardwareScore(
        cpu: 'AMD Ryzen 7 5800X 8-Core Processor',
        gpu: 'NVIDIA GeForce RTX 4070',
        cores: 8,
        isWin11: true,
      );

      expect(score, greaterThanOrEqualTo(75));
      final tier = ThemeProvider.calculateTierFromScore(score);
      expect(tier, equals(HardwareTier.ultra));
    });
  });

  group('ThemeProvider Hardware Profiling & Preferences Persistence', () {
    test(
      'Lite overrides old tuning after disk reload, including dropdowns',
      () async {
        await AppPreferences().setGlassTuning(cardBlur: 30, dialogBlur: 28);
        await AppPreferences().setPerfTierMode('lite');
        await AppPreferences().load();
        final theme = ThemeProvider();
        expect(theme.perfMode, PerfTierMode.lite);
        expect(theme.cardBlur, 0);
        expect(theme.dialogBlur, 0);
        expect(theme.dropdownBlur, 0);
        expect(theme.dropdownOpacity, 0.98);
        theme.dispose();
      },
    );

    test(
      'Balanced dropdown defaults survive saved custom card tuning',
      () async {
        await AppPreferences().setGlassTuning(cardBlur: 7);
        await AppPreferences().setPerfTierMode('balanced');
        await AppPreferences().load();
        final theme = ThemeProvider();
        expect(theme.cardBlur, 7);
        expect(theme.dropdownBlur, 12);
        expect(theme.dropdownOpacity, 0.94);
        theme.dispose();
      },
    );

    test('Cleared tuning does not reappear from disk', () async {
      await AppPreferences().setGlassTuning(cardBlur: 30, dialogBlur: 28);
      await AppPreferences().clearGlassTuning();
      await AppPreferences().load();
      expect(AppPreferences().cardBlur, isNull);
      expect(AppPreferences().dialogBlur, isNull);
    });

    test(
      'ThemeProvider loads registry info and sets HardwareTier.lite for N100',
      () {
        ThemeProvider.registryQueryOverride = (key, value) {
          if (value == 'ProcessorNameString') return 'Intel(R) N100';
          if (value == 'DriverDesc') return 'Intel(R) UHD Graphics';
          return null;
        };

        final provider = ThemeProvider();
        expect(provider.cpuModel, equals('Intel(R) N100'));
        expect(provider.gpuModel, equals('Intel(R) UHD Graphics'));
        expect(provider.detectedTier, equals(HardwareTier.lite));
        expect(provider.effectiveTier, equals(HardwareTier.lite));
        expect(provider.cardBlur, equals(0.0));
        expect(provider.dialogBlur, equals(0.0));
        expect(provider.dropdownBlur, equals(0.0));
      },
    );

    test(
      'Persisting perfTierMode saves to AppPreferences and reloads',
      () async {
        final provider = ThemeProvider();
        expect(provider.perfMode, equals(PerfTierMode.auto));

        await provider.setPerfTierMode(PerfTierMode.lite);
        expect(provider.perfMode, equals(PerfTierMode.lite));
        expect(provider.effectiveTier, equals(HardwareTier.lite));
        expect(AppPreferences().perfTierMode, equals('lite'));

        // New instance should read 'lite' from preferences
        final reloadedProvider = ThemeProvider();
        expect(reloadedProvider.perfMode, equals(PerfTierMode.lite));
        expect(reloadedProvider.effectiveTier, equals(HardwareTier.lite));
      },
    );
  });

  group('Widget Zero-Blur Fast Path Verification', () {
    testWidgets('GlassSurface omits BackdropFilter entirely when in Lite mode', (
      tester,
    ) async {
      ThemeProvider.registryQueryOverride = (key, value) {
        if (value == 'ProcessorNameString') return 'Intel(R) N100';
        if (value == 'DriverDesc') return 'Intel(R) UHD Graphics';
        return null;
      };

      final theme = ThemeProvider();
      await tester.runAsync(() => theme.setPerfTierMode(PerfTierMode.lite));

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: const MaterialApp(
            home: Scaffold(
              body: GlassSurface(child: Text('Performance Test Card')),
            ),
          ),
        ),
      );

      // Verify no BackdropFilter exists in the widget tree for GlassSurface in Lite mode
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Performance Test Card'), findsOneWidget);
    });

    testWidgets('GlassSurface renders BackdropFilter when in Ultra mode', (
      tester,
    ) async {
      final theme = ThemeProvider();
      await tester.runAsync(() => theme.setPerfTierMode(PerfTierMode.ultra));

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: const MaterialApp(
            home: Scaffold(body: GlassSurface(child: Text('Ultra Glass Card'))),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Ultra Glass Card'), findsOneWidget);
    });

    testWidgets(
      'MeshBackground renders lightweight gradient without ImageFiltered in Lite mode',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MeshBackground(
                colors: win10DarkColors,
                enableAnimation: false,
                isLite: true, // Lite mode
              ),
            ),
          ),
        );

        // Verify no heavy ImageFiltered or MeshOrb widgets exist when enableAnimation is false
        expect(find.byType(ImageFiltered), findsNothing);
        expect(find.byType(MeshOrb), findsNothing);
      },
    );

    testWidgets(
      'MeshBackground renders 3 MeshOrbs with ImageFiltered when animation enabled',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MeshBackground(
                colors: win10DarkColors,
                enableAnimation: true,
              ),
            ),
          ),
        );

        expect(find.byType(MeshOrb), findsNWidgets(3));
        expect(find.byType(ImageFiltered), findsNWidgets(3));
      },
    );
  });
}
