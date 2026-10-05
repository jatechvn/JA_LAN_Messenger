import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/ui/main_messenger_window.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/app_power_scope.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/close_action_dialog.dart';

class QuietCoordinator extends MessengerCoordinator {
  @override
  Future<void> initialize() async {}
}

void main() {
  testWidgets(
    'real close handler confirms tray, remembers and guards duplicate close',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ja_close_test_'),
      ))!;
      final prefs = AppPreferences();
      prefs.setCustomFileForTesting(File('${dir.path}/prefs.json'));
      final power = AppPowerManager.instance;
      power.resetForTesting(enableIdleSleep: false);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var visible = true;
      var hides = 0;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (call.method == 'isVisible' || call.method == 'isFocused') {
            return visible;
          }
          if (call.method == 'isMinimized') return false;
          if (call.method == 'hide') {
            hides++;
            visible = false;
          }
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('tray_manager'),
        (_) async => null,
      );
      ThemeProvider.registryQueryOverride = (_, _) => null;
      final lang = LanguageProvider();
      final theme = ThemeProvider();
      final coordinator = QuietCoordinator();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider<MessengerCoordinator>.value(
              value: coordinator,
            ),
          ],
          child: MaterialApp(
            builder: (_, child) => AppPowerScope(child: child!),
            home: const MainMessengerWindow(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      power.onWindowBlur();
      final listener =
          tester.state(find.byType(MainMessengerWindow)) as WindowListener;
      await tester.runAsync(() async {
        listener.onWindowClose();
        listener.onWindowClose();
      });
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(CloseActionDialog), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text(lang.tr('rememberChoice')));
      await tester.tap(find.text(lang.tr('confirm')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.runAsync(() => prefs.flush());
      await tester.pump();
      expect(hides, 1);
      expect(visible, isFalse);
      expect(prefs.rememberCloseBehavior, isTrue);
      await tester.runAsync(() => prefs.load());
      expect(prefs.closeBehavior, 'minimize');
      await tester.runAsync(() async {
        listener.onWindowClose();
      });
      await tester.pump();
      expect(hides, 2);
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
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
