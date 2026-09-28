import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/tray_window_toggle.dart';

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

  setUp(() {
    visible = true;
    minimized = false;
    calls = [];
    gate = null;
    fail = false;
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
          visible = false;
        case 'show':
          visible = true;
        case 'restore':
          minimized = false;
        case 'focus':
          break;
        default:
          throw StateError('Unexpected window query: ${call.method}');
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'visible window hides without querying focus, next click shows',
    () async {
      final toggle = TrayWindowToggle();
      await toggle.toggle();
      expect(visible, isFalse);
      expect(calls, ['isVisible', 'isMinimized', 'hide']);
      await toggle.toggle();
      expect(visible, isTrue);
      expect(calls, contains('focus'));
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
}
