import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_file_preview_dialog.dart';
import 'file_preview_inspector_test.dart' show zipFixture, workbookFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleTextFile;
  late File sampleBinaryFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('smart_preview_test_');
    sampleTextFile = File('${tempDir.path}/test_readme.md');
    sampleTextFile.writeAsStringSync('# Test Markdown Content\nLine 2 text.');

    sampleBinaryFile = File('${tempDir.path}/data_sample.bin');
    sampleBinaryFile.writeAsBytesSync([
      0x50,
      0x4B,
      0x03,
      0x04,
      0x14,
      0x00,
      0x06,
      0x00,
      0x08,
      0x00,
      0x00,
      0x00,
      0x21,
      0x00,
      0x70,
      0x82,
      0x48,
      0x65,
      0x6C,
      0x6C,
      0x6F,
      0x20,
      0x57,
      0x6F,
      0x72,
      0x6C,
      0x64,
      0x21,
      0x00,
      0x01,
      0x02,
      0x03,
    ]);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Smart File Preview Logic & Unit Tests', () {
    test('generateHexDump produces correct offset, hex, and ascii format', () {
      final bytes = [
        0x50, 0x4B, 0x03, 0x04, // PK..
        0x41, 0x42, 0x43, 0x44, // ABCD
      ];
      final dump = generateHexDump(bytes);
      expect(dump, contains('00000000'));
      expect(dump, contains('50 4B 03 04 41 42 43 44'));
      expect(dump, contains('|PK..ABCD|'));
    });

    test('generateHexDump handles empty bytes safely', () {
      final dump = generateHexDump([]);
      expect(dump, isEmpty);
    });

    test(
      'readZipCentralDirectory returns empty list for non-existent file',
      () {
        final entries = readZipCentralDirectory('non_existent_file_12345.zip');
        expect(entries, isEmpty);
      },
    );

    test('readZipCentralDirectory safely handles non-zip binary file', () {
      final entries = readZipCentralDirectory(sampleBinaryFile.path);
      expect(entries, isEmpty);
    });

    test(
      'All new localization keys exist across VI, EN, and ZH dictionaries',
      () {
        final requiredKeys = [
          'copyFile',
          'fileCopied',
          'tabOverview',
          'tabContents',
          'tabHexView',
          'sha256Hash',
          'hashCopied',
          'openWithAppHint',
          'sheetsFound',
          'archiveFilesCount',
          'createdTime',
          'modifiedTime',
          'pressEnterToOpen',
          'previewDefaultAppUnknown',
          'previewAssociation',
          'previewHashError',
          'previewHashLoading',
          'previewCreated',
          'previewFormatInfo',
          'previewSpreadsheet',
          'previewReady',
          'previewContentsHint',
          'previewSheetIndex',
          'previewEmptyData',
          'previewArchiveSizes',
          'previewTypePdf',
          'previewTypeWord',
          'previewTypePresentation',
          'previewTypeArchive',
          'previewTypeText',
          'previewTypeMarkdown',
          'previewTypeSource',
          'previewTypeConfig',
          'previewTypeScript',
          'previewTypeAudio',
          'previewTypeVideo',
          'previewTypeExecutable',
          'previewTypeFile',
        ];

        for (final appLang in AppLanguage.values) {
          final lang = LanguageProvider();
          lang.setLanguage(appLang);
          for (final key in requiredKeys) {
            final translated = lang.tr(key);
            expect(
              translated,
              isNot(equals(key)),
              reason: 'Missing translation for key "$key" in "${appLang.code}"',
            );
            expect(translated, isNotEmpty);
          }
        }
      },
    );
  });

  Widget buildTestApp({
    required Widget child,
    AppLanguage language = AppLanguage.vi,
  }) {
    final lang = LanguageProvider();
    lang.setLanguage(language);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: lang),
      ],
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('GlassFilePreviewDialog Widget Tests', () {
    testWidgets(
      'copy-file failure actually copies path, and dismissal is safe',
      (tester) async {
        final gate = Completer<Object?>();
        var delay = false;
        String? copiedText;
        const pasteboard = MethodChannel('pasteboard');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pasteboard,
          (call) async {
            if (delay) return gate.future;
            throw PlatformException(code: 'clipboard_failed');
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            pasteboard,
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        await tester.pumpWidget(
          buildTestApp(
            child: GlassFilePreviewDialog(
              filePath: sampleTextFile.path,
              fileName: 'test_readme.md',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sao chép tệp'));
        await tester.pumpAndSettle();
        expect(copiedText, sampleTextFile.path);
        delay = true;
        await tester.tap(find.text('Sao chép tệp'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        gate.completeError(PlatformException(code: 'late_failure'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'English XLSX inspector shows real sheet names after archive loading',
      (tester) async {
        final file = File('${tempDir.path}/renamed.xlsx')
          ..writeAsBytesSync(zipFixture(workbookFixture()));
        await tester.pumpWidget(
          buildTestApp(
            language: AppLanguage.en,
            child: GlassFilePreviewDialog(
              filePath: file.path,
              fileName: 'renamed.xlsx',
            ),
          ),
        );
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Format information'), findsOneWidget);
        expect(find.text('Đặc tính định dạng'), findsNothing);
        await tester.tap(find.text('2 worksheets').first);
        await tester.pumpAndSettle();
        expect(find.text('Doanh thu & Chi phí'), findsOneWidget);
        expect(find.text('预算'), findsOneWidget);
        expect(find.text('Sheet #1'), findsOneWidget);
        expect(find.text('Trang tính #1'), findsNothing);
      },
    );
    testWidgets('renders text preview for text-based file', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: GlassFilePreviewDialog(
            filePath: sampleTextFile.path,
            fileName: 'test_readme.md',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GlassFilePreviewDialog), findsOneWidget);
      expect(find.textContaining('Test Markdown Content'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('Sao chép tệp'), findsOneWidget);
      expect(find.text('Mở tệp'), findsOneWidget);
    });

    testWidgets('renders smart bento inspector with tabs for binary file', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          child: GlassFilePreviewDialog(
            filePath: sampleBinaryFile.path,
            fileName: 'data_sample.bin',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GlassFilePreviewDialog), findsOneWidget);
      expect(find.text('Tổng quan'), findsOneWidget);
      expect(find.text('Mã Hex'), findsOneWidget);
      expect(find.text('Ứng dụng mở mặc định'), findsOneWidget);
      expect(find.text('Mã băm SHA-256'), findsOneWidget);

      // Switch to Hex View tab
      await tester.tap(find.text('Mã Hex'));
      await tester.pumpAndSettle();

      // Check hex dump is rendered
      expect(find.textContaining('00000000'), findsOneWidget);
      expect(find.textContaining('Hello World!'), findsOneWidget);
    });

    testWidgets(
      'clicking on backdrop outside the dialog card closes the dialog',
      (tester) async {
        bool dialogClosed = false;

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showGeneralDialog(
                      context: context,
                      barrierDismissible: true,
                      barrierLabel: 'TestPreview',
                      pageBuilder: (ctx, anim1, anim2) =>
                          GlassFilePreviewDialog(
                            filePath: sampleBinaryFile.path,
                            fileName: 'data_sample.bin',
                          ),
                    ).then((_) {
                      dialogClosed = true;
                    });
                  },
                  child: const Text('Launch Preview'),
                );
              },
            ),
          ),
        );

        // Open the dialog
        await tester.tap(find.text('Launch Preview'));
        await tester.pumpAndSettle();

        expect(find.byType(GlassFilePreviewDialog), findsOneWidget);
        expect(dialogClosed, isFalse);

        // Tap at the outer margin (top-left outside the 680x540 card)
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Dialog should be dismissed!
        expect(dialogClosed, isTrue);
        expect(find.byType(GlassFilePreviewDialog), findsNothing);
      },
    );

    testWidgets('clicking inside the dialog card does NOT close the dialog', (
      tester,
    ) async {
      bool dialogClosed = false;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: 'TestPreview',
                    pageBuilder: (ctx, anim1, anim2) => GlassFilePreviewDialog(
                      filePath: sampleBinaryFile.path,
                      fileName: 'data_sample.bin',
                    ),
                  ).then((_) {
                    dialogClosed = true;
                  });
                },
                child: const Text('Launch Preview'),
              );
            },
          ),
        ),
      );

      // Open the dialog
      await tester.tap(find.text('Launch Preview'));
      await tester.pumpAndSettle();

      expect(find.byType(GlassFilePreviewDialog), findsOneWidget);
      expect(dialogClosed, isFalse);

      // Tap on the card center
      await tester.tap(find.text('Tổng quan'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(dialogClosed, isFalse);
      expect(find.byType(GlassFilePreviewDialog), findsOneWidget);
    });

    testWidgets('pressing Escape key closes the dialog', (tester) async {
      bool dialogClosed = false;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: 'TestPreview',
                    pageBuilder: (ctx, anim1, anim2) => GlassFilePreviewDialog(
                      filePath: sampleBinaryFile.path,
                      fileName: 'data_sample.bin',
                    ),
                  ).then((_) {
                    dialogClosed = true;
                  });
                },
                child: const Text('Launch Preview'),
              );
            },
          ),
        ),
      );

      // Open the dialog
      await tester.tap(find.text('Launch Preview'));
      await tester.pumpAndSettle();

      expect(find.byType(GlassFilePreviewDialog), findsOneWidget);
      expect(dialogClosed, isFalse);

      // Send Escape key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(dialogClosed, isTrue);
      expect(find.byType(GlassFilePreviewDialog), findsNothing);
    });
  });
}
