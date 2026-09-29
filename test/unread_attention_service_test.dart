import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/unread_attention_service.dart';

void main() {
  testWidgets('blinks repeatedly, updates badge and stops only at zero', (
    tester,
  ) async {
    final icons = <String>[];
    final flashes = <bool>[];
    final service = UnreadAttentionService(
      setIcon: (path) async => icons.add(path),
      badgePath: (count) async => 'badge-$count',
      flashTaskbar: (bright) async => flashes.add(bright),
    );
    service.update(2);
    await tester.pump();
    expect(icons.last, 'badge-2');
    for (var i = 0; i < 8; i++) {
      service.update(
        2,
      ); // Unrelated coordinator notifications cannot reset timer.
      await tester.pump(UnreadAttentionService.interval);
    }
    expect(icons, [
      'badge-2',
      UnreadAttentionService.normalIcon,
      'badge-2',
      UnreadAttentionService.normalIcon,
      'badge-2',
      UnreadAttentionService.normalIcon,
      'badge-2',
      UnreadAttentionService.normalIcon,
      'badge-2',
    ]);
    expect(flashes, [true]); // Native timer must not restart on tray ticks.
    service.update(1);
    await tester.pump();
    expect(icons.last, 'badge-1');
    expect(flashes, [
      true,
    ]); // A changed badge count must not restart it either.
    service.update(0);
    await tester.pump();
    expect(icons.last, UnreadAttentionService.normalIcon);
    expect(flashes, [true, false]);
    final writes = icons.length;
    await tester.pump(const Duration(seconds: 5));
    expect(icons.length, writes);
    service.dispose();
    await tester.pump();
    expect(flashes, [true, false]);
  });

  testWidgets('late badge cannot restore unread icon after reading/disposal', (
    tester,
  ) async {
    for (final dispose in [false, true]) {
      final badge = Completer<String?>();
      final icons = <String>[];
      final flashes = <bool>[];
      final service = UnreadAttentionService(
        setIcon: (path) async => icons.add(path),
        badgePath: (_) => badge.future,
        flashTaskbar: (bright) async => flashes.add(bright),
      );
      service.update(3);
      if (dispose) {
        service.dispose();
      } else {
        service.update(0);
      }
      badge.complete('obsolete');
      await tester.pump();
      expect(icons, [UnreadAttentionService.normalIcon]);
      expect(flashes, [false]);
      service.dispose();
      await tester.pump();
    }
  });

  testWidgets(
    'slow writes are serialized and tray errors do not block taskbar',
    (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      var active = 0;
      var maximum = 0;
      final icons = <String>[];
      final flashes = <bool>[];
      final service = UnreadAttentionService(
        badgePath: (n) async => 'badge-$n',
        setIcon: (path) async {
          active++;
          if (active > maximum) maximum = active;
          try {
            if (++calls == 1) await gate.future;
            icons.add(path);
            if (calls == 2) throw StateError('tray temporarily unavailable');
          } finally {
            active--;
          }
        },
        flashTaskbar: (bright) async => flashes.add(bright),
      );
      service.update(5);
      await tester.pump();
      await tester.pump(UnreadAttentionService.interval);
      service.update(0);
      gate.complete();
      await tester.pump();
      expect(maximum, 1);
      expect(icons.last, UnreadAttentionService.normalIcon);
      expect(flashes.last, false);
      service.update(1);
      await tester.pump();
      expect(icons.last, 'badge-1');
      expect(flashes.last, true);
      service.dispose();
      await tester.pump();
    },
  );
}
