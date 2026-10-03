import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/app_power_scope.dart';

class OrdinaryTicker extends StatefulWidget {
  const OrdinaryTicker({super.key});
  @override
  State<OrdinaryTicker> createState() => OrdinaryTickerState();
}

class OrdinaryTickerState extends State<OrdinaryTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  int ticks = 0;
  @override
  void initState() {
    super.initState();
    controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() {
            ticks++;
          })
          ..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manager = AppPowerManager.instance;
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => manager.resetForTesting(enableIdleSleep: false));
  tearDown(() {
    manager.resetForTesting(enableIdleSleep: false);
    messenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'initial hidden snapshot and late native focus cannot undo hide/blur/dispose',
    () async {
      var hidden = true;
      Completer<bool>? delayed;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'isVisible':
            return !hidden;
          case 'isMinimized':
            return false;
          case 'isFocused':
            return delayed == null ? true : await delayed.future;
          case 'hide':
            hidden = true;
            return null;
        }
        return null;
      });
      await manager.synchronizeNative();
      expect(manager.shouldAnimateIndicators, isFalse);
      hidden = false;
      manager.onWindowFocus();
      delayed = Completer<bool>();
      final pending = manager.synchronizeNative();
      await manager.hideWindow();
      delayed.complete(true);
      await pending;
      manager.onLifecycleStateChanged(AppLifecycleState.resumed);
      expect(manager.isWindowVisible, isFalse);
      expect(manager.shouldAnimateIndicators, isFalse);
      manager.onWindowRestore();
      manager.onWindowFocus();
      delayed = Completer<bool>();
      final blurred = manager.synchronizeNative();
      manager.onWindowBlur();
      delayed.complete(true);
      await blurred;
      expect(manager.shouldAnimateIndicators, isFalse);
      var alive = true;
      delayed = Completer<bool>();
      final disposed = manager.synchronizeNative(isAlive: () => alive);
      alive = false;
      delayed.complete(true);
      await disposed;
      expect(manager.shouldAnimateIndicators, isFalse);
    },
  );
  for (final initiallyHidden in [false, true]) {
    testWidgets(
      'root gate mutes Navigator and overlay tickers, hidden=$initiallyHidden',
      (tester) async {
        manager.resetForTesting(
          isWindowVisible: !initiallyHidden,
          enableIdleSleep: false,
        );
        final navigator = GlobalKey<NavigatorState>();
        final key = GlobalKey<OrdinaryTickerState>();
        final overlayKey = GlobalKey<OrdinaryTickerState>();
        var businessTicks = 0;
        final business = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => businessTicks++,
        );
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            builder: (_, child) => AppPowerScope(child: child!),
            home: OrdinaryTicker(key: key),
          ),
        );
        final entry = OverlayEntry(
          builder: (_) => OrdinaryTicker(key: overlayKey),
        );
        navigator.currentState!.overlay!.insert(entry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        if (initiallyHidden) expect(key.currentState!.ticks, 0);
        manager.onWindowFocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(key.currentState!.ticks, greaterThan(0));
        for (final pause in [manager.onWindowBlur, manager.onWindowMinimize]) {
          pause();
          await tester.pump();
          final ticks = key.currentState!.ticks;
          final overlayTicks = overlayKey.currentState!.ticks;
          final previousBusiness = businessTicks;
          await tester.pump(const Duration(seconds: 1));
          expect(key.currentState!.ticks, ticks);
          expect(overlayKey.currentState!.ticks, overlayTicks);
          expect(businessTicks, greaterThan(previousBusiness));
          manager.onWindowRestore();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(key.currentState!.ticks, ticks);
          manager.onWindowFocus();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(key.currentState!.ticks, greaterThan(ticks));
        }
        business.cancel();
        entry.remove();
        entry.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'hide and show from different callers serialize; hide suppresses stale focus',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final calls = <String>[];
      var visible = true;
      var focused = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'hide':
            entered.complete();
            await release.future;
            visible = false;
            focused = false;
            return null;
          case 'show':
            visible = true;
            return null;
          case 'focus':
            focused = true;
            return null;
          case 'isVisible':
            return visible;
          case 'isMinimized':
            return false;
          case 'isFocused':
            return focused;
        }
        return null;
      });
      final hide = manager.hideWindow();
      await entered.future;
      final show = manager.showWindow();
      manager.onWindowFocus();
      expect(manager.shouldAnimateIndicators, isFalse);
      expect(calls, isNot(contains('show')));
      release.complete();
      await hide;
      await show;
      expect(calls, containsAllInOrder(['hide', 'show', 'focus']));
      expect(manager.shouldAnimateIndicators, isTrue);
    },
  );
  testWidgets('real idle timer sleeps, interaction rearms, focus wakes', (
    tester,
  ) async {
    manager.configure(enableIdleSleep: true, idleTimeoutSeconds: 12);
    await tester.pump(const Duration(seconds: 11));
    expect(manager.isUserIdle, isFalse);
    manager.recordUserInteraction(
      now: DateTime.now().add(const Duration(seconds: 1)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(manager.isUserIdle, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(manager.isUserIdle, isTrue);
    expect(manager.shouldAnimateIndicators, isTrue);
    expect(manager.shouldAnimateBackground, isFalse);
    manager.onWindowFocus();
    expect(manager.shouldAnimateBackground, isTrue);
    manager.configure(idleTimeoutSeconds: 30);
    await tester.pump(const Duration(seconds: 29));
    expect(manager.isUserIdle, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(manager.isUserIdle, isTrue);
    manager.resetForTesting(enableIdleSleep: false);
  });
}
