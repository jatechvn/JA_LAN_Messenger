import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';

void main() {
  group('AppPowerManager Tests', () {
    late AppPowerManager manager;

    setUp(() {
      manager = AppPowerManager.instance;
      manager.resetForTesting();
    });

    test(
      'Initial state: window is focused, visible, not minimized, not idle',
      () {
        expect(manager.isWindowFocused, isTrue);
        expect(manager.isWindowVisible, isTrue);
        expect(manager.isWindowMinimized, isFalse);
        expect(manager.isUserIdle, isFalse);
        expect(manager.shouldAnimateBackground, isTrue);
        expect(manager.shouldAnimateIndicators, isTrue);
        expect(manager.shouldAnimateMarquee, isTrue);
      },
    );

    test('onWindowBlur() immediately pauses all notifiers', () {
      manager.onWindowBlur();

      expect(manager.isWindowFocused, isFalse);
      expect(manager.shouldAnimateBackground, isFalse);
      expect(manager.shouldAnimateIndicators, isFalse);
      expect(manager.shouldAnimateMarquee, isFalse);
    });

    test('onWindowFocus() resumes all notifiers', () {
      manager.onWindowBlur();
      expect(manager.shouldAnimateBackground, isFalse);

      manager.onWindowFocus();
      expect(manager.isWindowFocused, isTrue);
      expect(manager.shouldAnimateBackground, isTrue);
      expect(manager.shouldAnimateIndicators, isTrue);
      expect(manager.shouldAnimateMarquee, isTrue);
    });

    test('onWindowMinimize() pauses all notifiers', () {
      manager.onWindowMinimize();

      expect(manager.isWindowMinimized, isTrue);
      expect(manager.isWindowVisible, isFalse);
      expect(manager.shouldAnimateBackground, isFalse);
      expect(manager.shouldAnimateIndicators, isFalse);
      expect(manager.shouldAnimateMarquee, isFalse);
    });

    test('onWindowRestore() makes window visible, respects focus state', () {
      manager.onWindowMinimize();
      expect(manager.shouldAnimateBackground, isFalse);

      manager.onWindowRestore();
      expect(manager.isWindowMinimized, isFalse);
      expect(manager.isWindowVisible, isTrue);
      // Restore is visibility, not proof of focus from the old session.
      expect(manager.shouldAnimateBackground, isFalse);
      expect(manager.shouldAnimateIndicators, isFalse);
      expect(manager.shouldAnimateMarquee, isFalse);
      manager.onWindowFocus();
      expect(manager.shouldAnimateIndicators, isTrue);

      // If blurred before restore
      manager.onWindowBlur();
      manager.onWindowMinimize();
      manager.onWindowRestore();
      // Still not focused -> remains paused
      expect(manager.shouldAnimateBackground, isFalse);
      expect(manager.shouldAnimateIndicators, isFalse);
      expect(manager.shouldAnimateMarquee, isFalse);
    });

    test(
      'Idle timeout only pauses background, keeps indicators & marquee active',
      () {
        expect(manager.shouldAnimateBackground, isTrue);
        expect(manager.shouldAnimateIndicators, isTrue);
        expect(manager.shouldAnimateMarquee, isTrue);

        manager.triggerIdleTimeoutForTesting();

        expect(manager.isUserIdle, isTrue);
        expect(
          manager.shouldAnimateBackground,
          isFalse,
          reason: 'MeshOrb background must pause during idle',
        );
        expect(
          manager.shouldAnimateIndicators,
          isTrue,
          reason: 'Indicators must keep running during idle',
        );
        expect(
          manager.shouldAnimateMarquee,
          isTrue,
          reason: 'Marquee must keep running during idle',
        );
      },
    );

    test('recordUserInteraction() immediately wakes up from idle sleep', () {
      manager.triggerIdleTimeoutForTesting();
      expect(manager.isUserIdle, isTrue);
      expect(manager.shouldAnimateBackground, isFalse);

      manager.recordUserInteraction();

      expect(manager.isUserIdle, isFalse);
      expect(
        manager.shouldAnimateBackground,
        isTrue,
        reason: 'Background must wake up instantly on user interaction',
      );
      expect(manager.shouldAnimateIndicators, isTrue);
      expect(manager.shouldAnimateMarquee, isTrue);
    });

    test('configure(enableIdleSleep: false) disables idle sleep', () {
      manager.configure(enableIdleSleep: false);
      expect(manager.enableIdleSleep, isFalse);

      manager.triggerIdleTimeoutForTesting();

      // Because idle sleep is disabled, background remains active!
      expect(manager.shouldAnimateBackground, isTrue);
    });

    test('configure(idleTimeoutSeconds) updates timeout setting', () {
      manager.configure(idleTimeoutSeconds: 30);
      expect(manager.idleTimeoutSeconds, equals(30));
    });

    test('onLifecycleStateChanged maps states correctly', () {
      manager.onLifecycleStateChanged(AppLifecycleState.inactive);
      expect(manager.isWindowFocused, isFalse);
      expect(manager.shouldAnimateBackground, isFalse);

      manager.onWindowFocus();
      expect(manager.shouldAnimateBackground, isTrue);

      manager.onLifecycleStateChanged(AppLifecycleState.paused);
      expect(manager.isWindowVisible, isFalse);
      expect(manager.shouldAnimateBackground, isFalse);

      manager.onLifecycleStateChanged(AppLifecycleState.resumed);
      expect(manager.isWindowVisible, isTrue);
      expect(manager.shouldAnimateBackground, isTrue);
    });
    test('inactive then resumed restores focus; hidden/paused reset focus', () {
      manager.onLifecycleStateChanged(AppLifecycleState.inactive);
      manager.onLifecycleStateChanged(AppLifecycleState.resumed);
      expect(manager.shouldAnimateIndicators, isTrue);
      manager.onLifecycleStateChanged(AppLifecycleState.hidden);
      expect(manager.isWindowFocused, isFalse);
      expect(manager.shouldAnimateIndicators, isFalse);
      manager.onLifecycleStateChanged(AppLifecycleState.resumed);
      expect(manager.shouldAnimateIndicators, isTrue);
      manager.onLifecycleStateChanged(AppLifecycleState.paused);
      expect(manager.shouldAnimateIndicators, isFalse);
    });
  });
}
