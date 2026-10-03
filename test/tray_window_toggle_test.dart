import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/tray_window_toggle.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late bool visible;
  late bool minimized;
  late List<String> calls;
  Completer<void>? gate;
  var fail = false;
  var failHide = false;
  var focused = true;

  setUp(() {
    visible = true;
    minimized = false;
    calls = [];
    gate = null;
    fail = false;
    failHide = false;
    focused = true;
    AppPowerManager.instance.resetForTesting(enableIdleSleep: false);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isVisible':
          if (gate != null) await gate!.future;
          if (fail) throw PlatformException(code: 'test');
          return visible;
        case 'isMinimized':
          return minimized;
        case 'hide':
          if (failHide) throw PlatformException(code: 'hide-failed');
          visible = false;
          focused = false;
        case 'show':
          visible = true;
        case 'restore':
          minimized = false;
        case 'focus':
          focused = true;
          break;
        case 'isFocused':
          return focused;
        default:
          throw StateError('Unexpected window query: ${call.method}');
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    AppPowerManager.instance.resetForTesting(enableIdleSleep: false);
  });

  test(
    'visible window hides without querying focus, next click shows',
    () async {
      final toggle = TrayWindowToggle();
      await toggle.toggle();
      expect(visible, isFalse);
      expect(AppPowerManager.instance.shouldAnimateIndicators, isFalse);
      expect(calls, ['isVisible', 'isMinimized', 'hide']);
      await toggle.toggle();
      expect(visible, isTrue);
      expect(calls, contains('focus'));
      expect(AppPowerManager.instance.shouldAnimateIndicators, isTrue);
    },
  );

  test('minimized window restores instead of hiding', () async {
    minimized = true;
    await TrayWindowToggle().toggle();
    expect(minimized, isFalse);
    expect(visible, isTrue);
    expect(calls, containsAllInOrder(['restore', 'show', 'focus']));
    expect(calls, isNot(contains('hide')));
  });

  test('overlapping clicks do not run two toggles', () async {
    gate = Completer<void>();
    final toggle = TrayWindowToggle();
    final first = toggle.toggle();
    await toggle.toggle();
    gate!.complete();
    await first;
    expect(calls.where((c) => c == 'hide'), hasLength(1));
  });

  test('plugin failure releases the busy guard', () async {
    final toggle = TrayWindowToggle();
    fail = true;
    await expectLater(toggle.toggle(), throwsA(isA<PlatformException>()));
    fail = false;
    await toggle.toggle();
    expect(visible, isFalse);
  });
  test('hide failure reconciles a still-visible focused window', () async {
    failHide = true;
    await expectLater(
      TrayWindowToggle().toggle(),
      throwsA(isA<PlatformException>()),
    );
    expect(visible, isTrue);
    expect(AppPowerManager.instance.shouldAnimateIndicators, isTrue);
  });
  test('show without focus remains muted until real focus', () async {
    await AppPowerManager.instance.hideWindow();
    await AppPowerManager.instance.showWindow(requestFocus: false);
    expect(visible, isTrue);
    expect(AppPowerManager.instance.shouldAnimateIndicators, isFalse);
    AppPowerManager.instance.onWindowFocus();
    expect(AppPowerManager.instance.shouldAnimateIndicators, isTrue);
  });
}
