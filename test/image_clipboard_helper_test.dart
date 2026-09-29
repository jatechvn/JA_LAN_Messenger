import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/image_clipboard_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageClipboardHelper Tests', () {
    const channel = MethodChannel('pasteboard');
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            if (methodCall.method == 'writeImage') {
              return null;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('Non-existent file returns false safely without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(SizedBox));

      final result = await tester.runAsync(
        () => ImageClipboardHelper.copyImageToClipboard(
          context,
          filePath: r'C:\non_existent_folder\fake_image_12345.png',
          showToast: false,
        ),
      );

      expect(result, isFalse);
      expect(log, isEmpty);
    });

    testWidgets('Empty bytes return false safely', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(SizedBox));

      final result = await tester.runAsync(
        () => ImageClipboardHelper.copyImageToClipboard(
          context,
          imageBytes: Uint8List(0),
          showToast: false,
        ),
      );

      expect(result, isFalse);
      expect(log, isEmpty);
    });

    testWidgets('Valid bytes write to Pasteboard channel successfully', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(SizedBox));

      final dummyBytes = Uint8List.fromList([1, 2, 3, 4]);
      final result = await tester.runAsync(
        () => ImageClipboardHelper.copyImageToClipboard(
          context,
          imageBytes: dummyBytes,
          showToast: false,
        ),
      );

      expect(result, isTrue);
      expect(log.length, 1);
      expect(log.first.method, 'writeImage');
    });

    testWidgets('Temporary image file copies successfully', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('ja_test_');
      final tempFile = File('${tempDir.path}/test_img.png');
      tempFile.writeAsBytesSync([10, 20, 30, 40]);

      try {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())),
        );
        final context = tester.element(find.byType(SizedBox));

        final result = await tester.runAsync(
          () => ImageClipboardHelper.copyImageToClipboard(
            context,
            filePath: tempFile.path,
            showToast: false,
          ),
        );

        expect(result, isTrue);
        expect(log.length, 1);
        expect(log.first.method, 'writeImage');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
