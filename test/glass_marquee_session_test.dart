import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/bounce_marquee_text.dart';

void main() {
  group('Glass Marquee Session Epoch & Freeze Tests', () {
    late AppPowerManager manager;

    setUp(() {
      manager = AppPowerManager.instance;
      manager.resetForTesting(enableIdleSleep: false);
      addTearDown(() => manager.resetForTesting(enableIdleSleep: false));
    });

    testWidgets(
      'Marquee scrolls when overflowed, freezes offset on blur without ghost callbacks',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 100,
                  child: BounceMarqueeText(
                    text:
                        'This is a very long text that definitely overflows one hundred pixels container',
                    pauseStart: const Duration(milliseconds: 50),
                    pauseEnd: const Duration(milliseconds: 50),
                    velocity: 50.0,
                  ),
                ),
              ),
            ),
          ),
        );

        // Initial frame
        await tester.pumpAndSettle(const Duration(milliseconds: 20));
        final dynamic dynamicState = tester.state(
          find.byType(BounceMarqueeText),
        );
        final ScrollController scrollController = dynamicState.scrollController;

        expect(scrollController.hasClients, isTrue);
        final double maxScroll = scrollController.position.maxScrollExtent;
        expect(maxScroll, greaterThan(0.0), reason: 'Text must overflow');

        // Wait for pauseStart and start scrolling forward
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump(const Duration(milliseconds: 300));

        final double offset1 = scrollController.offset;
        expect(
          offset1,
          greaterThan(0.0),
          reason: 'Marquee must have started scrolling forward',
        );

        final int epochBeforeBlur = dynamicState.sessionEpoch;

        // Blur window -> Must freeze immediately and increment epoch
        manager.onWindowBlur();
        await tester.pump();

        expect(dynamicState.isPaused, isTrue);
        expect(dynamicState.sessionEpoch, greaterThan(epochBeforeBlur));

        final double frozenOffset = scrollController.offset;
        expect(frozenOffset, equals(offset1));

        // Pump 5 seconds while blurred -> verify ZERO ghost callbacks occur and offset never drifts
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        expect(
          scrollController.offset,
          equals(frozenOffset),
          reason: 'Offset must stay strictly frozen during blur',
        );

        // Focus window -> Must resume and continue scrolling from frozen offset
        manager.onWindowFocus();
        await tester.pump();

        expect(dynamicState.isPaused, isFalse);
        expect(dynamicState.sessionEpoch, greaterThan(epochBeforeBlur + 1));

        // Pump to let animation progress
        await tester.pump(const Duration(milliseconds: 300));
        final double resumedOffset = scrollController.offset;
        expect(
          resumedOffset,
          greaterThan(frozenOffset),
          reason: 'Must continue forward from frozen offset, not reset to 0',
        );
      },
    );

    testWidgets('Marquee does not animate if string fits within bounds', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                child: BounceMarqueeText(text: 'Short', velocity: 50.0),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final dynamic dynamicState = tester.state(find.byType(BounceMarqueeText));
      final ScrollController scrollController = dynamicState.scrollController;

      expect(scrollController.position.maxScrollExtent, equals(0.0));
      expect(scrollController.offset, equals(0.0));

      // Advance time
      await tester.pump(const Duration(seconds: 2));
      expect(scrollController.offset, equals(0.0));
    });
  });
}
