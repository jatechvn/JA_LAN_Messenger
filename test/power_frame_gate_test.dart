import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/power_aware_binding.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';

class PowerTestBinding extends AutomatedTestWidgetsFlutterBinding
    with PowerFrameGate {}

class TimerPaint extends StatefulWidget {
  const TimerPaint({super.key});
  @override
  State<TimerPaint> createState() => TimerPaintState();
}

class TimerPaintState extends State<TimerPaint> {
  int updates = 0;
  int builds = 0;
  late final Timer timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() => updates++);
    });
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    return const SizedBox();
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }
}

void main() {
  final binding = PowerTestBinding();
  final power = AppPowerManager.instance;
  setUp(() => power.resetForTesting(enableIdleSleep: false));
  tearDown(() => power.resetForTesting(enableIdleSleep: false));
  testWidgets(
    'inactive suppresses timer-driven frames; updates continue and resume paints dirty UI',
    (tester) async {
      final key = GlobalKey<TimerPaintState>();
      await tester.pumpWidget(TimerPaint(key: key));
      await tester.pump(const Duration(milliseconds: 100));
      power.onWindowBlur();
      await tester
          .pump(); // Allow the single already-scheduled frame to settle.
      final builds = key.currentState!.builds;
      final updates = key.currentState!.updates;
      expect(binding.framesEnabled, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(key.currentState!.updates, greaterThan(updates));
      expect(key.currentState!.builds, builds);
      expect(binding.hasScheduledFrame, isFalse);
      power.onWindowFocus();
      expect(binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(key.currentState!.builds, greaterThan(builds));
      power.onWindowMinimize();
      await tester.pump();
      expect(binding.framesEnabled, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(binding.hasScheduledFrame, isFalse);
      power.onWindowRestore();
      expect(binding.framesEnabled, isFalse);
      power.onWindowFocus();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('focused idle still allows responsive indicator frames', (
    tester,
  ) async {
    power.configure(enableIdleSleep: true);
    power.triggerIdleTimeoutForTesting();
    expect(power.shouldAnimateBackground, isFalse);
    expect(binding.framesEnabled, isTrue);
    await tester.pumpWidget(const SizedBox());
    power.configure(enableIdleSleep: false);
  });
}
