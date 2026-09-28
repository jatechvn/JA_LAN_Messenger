import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:ja_lan_messenger/modules/services/app_icon_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/tray_badge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrayBadgeService Unit Tests', () {
    test('badge preserves source icon pixels outside badge area', () async {
      final source = await File('assets/app_icon.ico').readAsBytes();
      final bundled = await rootBundle.load('assets/app_icon.ico');
      expect(bundled.buffer.asUint8List(), source);
      final base = await decodeAppIcon(source);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(base.width.toDouble(), base.height.toDouble()),
        const Size(32, 32),
      );
      canvas.drawImageRect(
        base,
        Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
        Alignment.center.inscribe(
          fitted.destination,
          const Rect.fromLTWH(0, 0, 32, 32),
        ),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final expected = await picture.toImage(32, 32);
      final path = await TrayBadgeService.getBadgeIconPath(3);
      final actual = await decodeAppIcon(await File(path!).readAsBytes());
      // Match PNG encode/decode quantization at translucent edges.
      final encoded = await expected.toByteData(format: ui.ImageByteFormat.png);
      final codec = await ui.instantiateImageCodec(
        encoded!.buffer.asUint8List(),
      );
      final normalized = (await codec.getNextFrame()).image;
      final expectedBytes = (await normalized.toByteData())!.buffer
          .asUint8List();
      normalized.dispose();
      codec.dispose();
      final actualBytes = (await actual.toByteData())!.buffer.asUint8List();
      expect(
        actualBytes.sublist(32 * 18 * 4),
        expectedBytes.sublist(32 * 18 * 4),
      );
      expect(actualBytes, isNot(equals(expectedBytes)));
      actual.dispose();
      expected.dispose();
      picture.dispose();
      base.dispose();
    });
    test('invalid ICO is rejected', () async {
      await expectLater(decodeAppIcon(Uint8List(4)), throwsFormatException);
      await expectLater(
        decodeAppIcon(Uint8List.fromList([0, 0, 1, 0, 1, 0])),
        throwsFormatException,
      );
    });
    test(
      'wrapPngAsIco creates valid Windows ICO header and directory entry',
      () {
        final dummyPng = Uint8List.fromList([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          1,
          2,
          3,
          4,
        ]);
        final icoBytes = TrayBadgeService.wrapPngAsIco(
          dummyPng,
          width: 32,
          height: 32,
        );

        // Header: 6 bytes
        expect(icoBytes.length, equals(6 + 16 + dummyPng.length));
        expect(icoBytes[0], equals(0)); // Reserved
        expect(icoBytes[1], equals(0));
        expect(icoBytes[2], equals(1)); // Type 1 = Icon
        expect(icoBytes[3], equals(0));
        expect(icoBytes[4], equals(1)); // Count = 1 image
        expect(icoBytes[5], equals(0));

        // Directory Entry: 16 bytes
        expect(icoBytes[6], equals(32)); // Width
        expect(icoBytes[7], equals(32)); // Height
        expect(icoBytes[8], equals(0)); // Color count
        expect(icoBytes[9], equals(0)); // Reserved
        expect(icoBytes[10], equals(1)); // Color planes (1)
        expect(icoBytes[11], equals(0));
        expect(icoBytes[12], equals(32)); // Bits per pixel (32)
        expect(icoBytes[13], equals(0));

        // Size of image (little endian uint32)
        final expectedLen = dummyPng.length;
        expect(icoBytes[14], equals(expectedLen & 0xFF));
        expect(icoBytes[15], equals((expectedLen >> 8) & 0xFF));
        expect(icoBytes[16], equals((expectedLen >> 16) & 0xFF));
        expect(icoBytes[17], equals((expectedLen >> 24) & 0xFF));

        // Offset of image (22 in little endian uint32)
        expect(icoBytes[18], equals(22));
        expect(icoBytes[19], equals(0));
        expect(icoBytes[20], equals(0));
        expect(icoBytes[21], equals(0));

        // Payload
        final payload = icoBytes.sublist(22);
        expect(payload, equals(dummyPng));
      },
    );

    test(
      'wrapPngAsIco handles dimensions >= 256 as 0 per ICO specification',
      () {
        final dummyPng = Uint8List.fromList([1, 2, 3, 4]);
        final icoBytes = TrayBadgeService.wrapPngAsIco(
          dummyPng,
          width: 256,
          height: 256,
        );
        expect(icoBytes[6], equals(0)); // 256 -> 0
        expect(icoBytes[7], equals(0)); // 256 -> 0
      },
    );

    test('getBadgeIconPath returns null for unreadCount <= 0', () async {
      expect(await TrayBadgeService.getBadgeIconPath(0), isNull);
      expect(await TrayBadgeService.getBadgeIconPath(-1), isNull);
    });

    test(
      'getBadgeIconPath generates valid .ico file for unread count',
      () async {
        final path1 = await TrayBadgeService.getBadgeIconPath(3);
        expect(path1, isNotNull);
        expect(path1!.endsWith('.ico'), isTrue);

        final file = File(path1);
        expect(file.existsSync(), isTrue);
        final bytes = await file.readAsBytes();
        expect(bytes.length, greaterThan(22));
        expect(bytes.sublist(0, 6), equals([0, 0, 1, 0, 1, 0]));

        // Test 9+ badge
        final path9Plus = await TrayBadgeService.getBadgeIconPath(15);
        expect(path9Plus, isNotNull);
        expect(path9Plus!.contains('9+'), isTrue);
        expect(File(path9Plus).existsSync(), isTrue);

        // Verify caching returns same path
        final cachedPath = await TrayBadgeService.getBadgeIconPath(3);
        expect(cachedPath, equals(path1));
      },
    );
  });
}
