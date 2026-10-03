import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_background.dart';

void main() {
  group('Glass Animation Resume & Direction Preservation Tests', () {
    late AppPowerManager manager;

    setUp(() {
      manager = AppPowerManager.instance;
      manager.resetForTesting(enableIdleSleep: false);
      addTearDown(() => manager.resetForTesting(enableIdleSleep: false));
    });

    testWidgets(
      'MeshOrb animates forward, pauses on blur, and preserves position',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MeshOrb(
                color: Colors.blue,
                size: 200,
                duration: Duration(seconds: 4),
                travel: Offset(100, 100),
              ),
            ),
          ),
        );

        // Start animation and advance
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final state1 = tester.state(find.byType(MeshOrb));
        final dynamic dynamicState1 = state1;
        final double value1 = dynamicState1.controller.value;
        expect(value1, greaterThan(0.0));
        expect(value1, lessThan(1.0));

        // Window blurs -> MeshOrb must stop
        manager.onWindowBlur();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final double value2 = dynamicState1.controller.value;
        expect(
          value2,
          equals(value1),
          reason: 'Animation must freeze completely during blur',
        );

        // Window focuses -> MeshOrb resumes forward from exact frozen position
        manager.onWindowFocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final double value3 = dynamicState1.controller.value;
        expect(
          value3,
          greaterThan(value2),
          reason: 'Animation must continue forward',
        );
      },
    );

    testWidgets('MeshOrb preserves reverse direction when paused mid-reverse', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MeshOrb(
              color: Colors.purple,
              size: 200,
              duration: Duration(seconds: 2),
              travel: Offset(50, 50),
            ),
          ),
        ),
      );

      final state = tester.state(find.byType(MeshOrb));
      final dynamic dynamicState = state;
      final AnimationController controller = dynamicState.controller;

      // Pump to completion so it flips to reverse
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // flips to reverse
      await tester.pump(const Duration(milliseconds: 500)); // advances in reverse

      expect(controller.status, equals(AnimationStatus.reverse));
      final double revValue1 = controller.value;
      expect(revValue1, lessThan(1.0));

      // Pause during reverse
      manager.onWindowBlur();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final double revValue2 = controller.value;
      expect(revValue2, equals(revValue1), reason: 'Frozen in reverse');

      // Resume -> Direction Preservation must continue in reverse, NOT snap forward!
      manager.onWindowFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final double revValue3 = controller.value;
      expect(
        controller.status,
        equals(AnimationStatus.reverse),
        reason: 'Must remain in reverse status',
      );
      expect(
        revValue3,
        lessThan(revValue2),
        reason: 'Must continue moving in reverse direction',
      );
    });

    testWidgets('MeshOrb initialized while window is blurred remains stopped', (
      tester,
    ) async {
      manager.onWindowBlur();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MeshOrb(
              color: Colors.cyan,
              size: 200,
              duration: Duration(seconds: 4),
              travel: Offset(50, 50),
            ),
          ),
        ),
      );

      final state = tester.state(find.byType(MeshOrb));
      final dynamic dynamicState = state;
      final AnimationController controller = dynamicState.controller;

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        controller.isAnimating,
        isFalse,
        reason: 'Must not animate while window is blurred',
      );
      expect(controller.value, equals(0.0));

      // Once focused, starts animating
      manager.onWindowFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.isAnimating, isTrue);
      expect(controller.value, greaterThan(0.0));
    });

    testWidgets('Idle sleep pauses MeshOrb, user interaction wakes it up', (
      tester,
    ) async {
      manager.resetForTesting(enableIdleSleep: true);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MeshOrb(
              color: Colors.blue,
              size: 200,
              duration: Duration(seconds: 4),
              travel: Offset(100, 100),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final dynamic dynamicState = tester.state(find.byType(MeshOrb));
      final double val1 = dynamicState.controller.value;
      expect(val1, greaterThan(0.0));

      // Trigger idle sleep
      manager.triggerIdleTimeoutForTesting();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final double val2 = dynamicState.controller.value;
      expect(val2, equals(val1), reason: 'Must pause when user is idle');

      // User interaction wakes up
      manager.recordUserInteraction();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final double val3 = dynamicState.controller.value;
      expect(
        val3,
        greaterThan(val2),
        reason: 'Must resume immediately upon user interaction',
      );
      manager.resetForTesting(enableIdleSleep: false);
    });
  });
}
