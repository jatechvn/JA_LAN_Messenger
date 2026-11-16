import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/power_aware_binding.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/app_power_scope.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/close_action_dialog.dart';
import 'package:ja_lan_messenger/modules/ui/main_messenger_window.dart';

class _ClosePowerBinding extends AutomatedTestWidgetsFlutterBinding
    with PowerFrameGate {}

class _QuietCloseCoordinator extends MessengerCoordinator {
  @override
  Future<void> initialize() async {}
}

void main() {
  _ClosePowerBinding();
  final power = AppPowerManager.instance;

  testWidgets('close confirmation removes route before frames are suspended', (
    tester,
  ) async {
    power.resetForTesting(enableIdleSleep: false);
    ThemeProvider.registryQueryOverride = (_, _) => null;
    final theme = ThemeProvider();
    final lang = LanguageProvider();
    final navigator = GlobalKey<NavigatorState>();
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => AppPowerScope(child: child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await CloseActionDialog.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(lang.tr('confirm')));
    // Hiding/missed native blur can suspend the Navigator before its reverse
    // transition ticks. Closing a modal must not depend on those future ticks.
    power.onWindowBlur();
    await tester.pump();
    expect(result?['action'], 'minimize');
    expect(navigator.currentState!.canPop(), isFalse);
    expect(find.byType(CloseActionDialog), findsNothing);
    power.onWindowFocus();
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
    lang.dispose();
    power.resetForTesting();
    ThemeProvider.registryQueryOverride = null;
  });

  testWidgets(
    'real close, tray restore and remembered close remain interactive under frame gate',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ja_close_gate_'),
      ))!;
      final prefs = AppPreferences()
        ..setCustomFileForTesting(File('${dir.path}/prefs.json'));
      power.resetForTesting(enableIdleSleep: false);
      ThemeProvider.registryQueryOverride = (_, _) => null;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var visible = true, focused = true;
      var hides = 0, clicks = 0;
      Future<void> waitForHide(int count) async {
        // Drain real preference I/O and its FakeAsync widget continuations.
        for (var attempt = 0; attempt < 100 && hides < count; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(hides, count);
      }

      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          switch (call.method) {
            case 'isVisible':
              return visible;
            case 'isFocused':
              return focused;
            case 'isMinimized':
              return false;
            case 'hide':
              visible = focused = false;
              hides++;
            case 'show':
              visible = true;
            case 'focus':
              focused = true;
          }
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('tray_manager'),
        (_) async => null,
      );
      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = _QuietCloseCoordinator();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider<MessengerCoordinator>.value(
              value: coordinator,
            ),
          ],
          child: MaterialApp(
            builder: (_, child) => AppPowerScope(child: child!),
            home: Column(
              children: [
                const Expanded(child: MainMessengerWindow()),
                TextButton(
                  onPressed: () => clicks++,
                  child: const Text('interaction probe'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      // Simulate a stale blur hint: native visibility/focus still belong to us.
      power.onWindowBlur();
      await tester.pump();
      final listener =
          tester.state(find.byType(MainMessengerWindow)) as WindowListener;
      await tester.runAsync(() async {
        listener.onWindowClose();
      });
      await tester.pump();
      expect(find.byType(CloseActionDialog), findsOneWidget);
      await tester.tap(find.text(lang.tr('rememberChoice')));
      await tester.pump();
      await tester.tap(find.text(lang.tr('confirm')));
      await tester.pump();
      await waitForHide(1);
      expect(hides, 1);
      expect(power.shouldAnimateIndicators, isFalse);
      expect(prefs.rememberCloseBehavior, isTrue);

      await tester.runAsync(() => power.showWindow());
      await tester.pump();
      expect(find.byType(CloseActionDialog), findsNothing);
      await tester.tap(find.text('interaction probe'));
      expect(clicks, 1);

      // Model restart/OTA: discard in-memory settings and load the same file.
      await tester.runAsync(() async {
        await prefs.flush();
        prefs.setCustomFileForTesting(File('${dir.path}/prefs.json'));
        await prefs.load();
      });
      await tester.runAsync(() async {
        listener.onWindowClose();
      });
      await waitForHide(2);
      expect(hides, 2);
      expect(find.byType(CloseActionDialog), findsNothing);

      await tester.runAsync(() => power.showWindow());
      await tester.pumpWidget(const SizedBox());
      coordinator.dispose();
      theme.dispose();
      lang.dispose();
      power.resetForTesting();
      prefs.setCustomFileForTesting(null);
      ThemeProvider.registryQueryOverride = null;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('tray_manager'),
        null,
      );
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
