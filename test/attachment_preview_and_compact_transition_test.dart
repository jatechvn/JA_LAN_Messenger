import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_file_preview_dialog.dart';
import 'package:ja_lan_messenger/modules/ui/main_messenger_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Localization File Preview Tests', () {
    test('All file preview keys exist across vi, en, zh', () {
      final lang = LanguageProvider();
      const keys = [
        'filePreview',
        'openWithApp',
        'fileSize',
        'fileType',
        'filePath',
        'copyPath',
        'pathCopied',
        'textPreviewTruncated',
        'binaryNoPreview',
        'fileNotFound',
      ];

      for (final code in ['vi', 'en', 'zh']) {
        lang.setLanguage(AppLanguage.fromCode(code));
        for (final key in keys) {
          final translated = lang.tr(key);
          expect(
            translated,
            isNot(equals(key)),
            reason: 'Key "$key" should be translated in "$code"',
          );
        }

        final formatted = lang.tr('textPreviewTruncated', ['48 KB']);
        expect(formatted, contains('48 KB'));
      }
    });
  });

  group('GlassFilePreviewDialog Widget Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('preview_widget_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('Displays text preview for text/code files', (tester) async {
      tester.view.physicalSize = const Size(320, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sampleFile = File('${tempDir.path}\\sample_code.dart');
      sampleFile.writeAsStringSync(
        'void main() {\n  print("Hello JA LAN");\n}',
      );

      final theme = ThemeProvider();
      final lang = LanguageProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlassFilePreviewDialog(
                filePath: sampleFile.path,
                fileName: 'sample_code.dart',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check file name & text content
      expect(find.text('sample_code.dart'), findsOneWidget);
      expect(find.textContaining('void main()'), findsOneWidget);
      expect(find.text(lang.tr('openWithApp')), findsOneWidget);
      expect(find.text(lang.tr('openFolder')), findsOneWidget);
      expect(find.text(lang.tr('copyPath')), findsOneWidget);

      // Tap copy path
      await tester.tap(find.text(lang.tr('copyPath')));
      await tester.pump();

      // Check snackbar with pathCopied
      expect(find.text(lang.tr('pathCopied')), findsOneWidget);
    });

    testWidgets('Displays binary card for binary/document files', (
      tester,
    ) async {
      final binFile = File('${tempDir.path}\\report.pdf');
      binFile.writeAsStringSync('%PDF-1.4 dummy content');

      final theme = ThemeProvider();
      final lang = LanguageProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlassFilePreviewDialog(
                filePath: binFile.path,
                fileName: 'report.pdf',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('report.pdf'), findsWidgets);
      expect(find.text(lang.tr('binaryNoPreview')), findsOneWidget);
      expect(find.text(lang.tr('openWithApp')), findsOneWidget);
    });

    testWidgets('Gracefully handles missing file', (tester) async {
      final theme = ThemeProvider();
      final lang = LanguageProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: GlassFilePreviewDialog(
                filePath: 'C:\\non_existent_folder\\ghost.txt',
                fileName: 'ghost.txt',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(lang.tr('fileNotFound')), findsWidgets);
    });
  });

  group('StagedAttachmentsBar Preview Tap Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('staged_tap_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('Tapping staged image thumbnail triggers preview lightbox', (
      tester,
    ) async {
      final theme = ThemeProvider();
      final lang = LanguageProvider();

      final imgFile = File('${tempDir.path}\\test_preview.png');
      imgFile.writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        ),
      );
      final docFile = File('${tempDir.path}\\notes.txt');
      docFile.writeAsStringSync('Hello preview notes');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StagedAttachmentsBar(files: [imgFile, docFile]),
            ),
          ),
        ),
      );
      await tester.pump();

      // Staged files count rendered
      expect(find.text(lang.tr('stagedFilesCount', [2])), findsOneWidget);

      // Tap the image item -> opens image lightbox dialog
      await tester.tap(find.byType(Image));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Lightbox is open and displays filename
      expect(find.text('test_preview.png'), findsWidgets);

      // Tap close / escape to dismiss
      final closeBtn = find.byIcon(Icons.close_rounded);
      expect(closeBtn, findsWidgets);
      await tester.tap(closeBtn.last);
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping staged document card triggers file preview dialog', (
      tester,
    ) async {
      final theme = ThemeProvider();
      final lang = LanguageProvider();

      final docFile = File('${tempDir.path}\\document.txt');
      docFile.writeAsStringSync('Testing document preview dialog');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: MaterialApp(
            home: Scaffold(body: StagedAttachmentsBar(files: [docFile])),
          ),
        ),
      );
      await tester.pump();

      // Tap the document card
      await tester.tap(find.text('document.txt'));
      await tester.pumpAndSettle();

      // Dialog opened: GlassFilePreviewDialog is in widget tree
      expect(find.byType(GlassFilePreviewDialog), findsOneWidget);
      expect(
        find.textContaining('Testing document preview dialog'),
        findsOneWidget,
      );

      // Dismiss dialog
      await tester.tap(find.byTooltip(lang.tr('closeDialog')));
      await tester.pumpAndSettle();
      expect(find.byType(GlassFilePreviewDialog), findsNothing);
    });
  });

  group('MainMessengerWindow Mode Transition Tests', () {
    late Directory tempDir;
    late File prefFile;
    late ChatHistoryService history;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('window_trans_test_');
      prefFile = File('${tempDir.path}\\prefs.json');
      AppPreferences().setCustomFileForTesting(prefFile);
      history = ChatHistoryService();
      history.setCustomDirectoryForTesting(tempDir);
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      history.setCustomDirectoryForTesting(null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'AnimatedSwitcher switches between standard_mode_view and compact_mode_view smoothly',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peer = PeerModel(
          id: '192.168.1.100:6475',
          name: 'Colleague',
          ip: '192.168.1.100',
          port: 6475,
          status: PeerStatus.online,
        );
        coordinator.peersMap[peer.id] = peer;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
              ChangeNotifierProvider.value(value: coordinator),
            ],
            child: const MaterialApp(home: MainMessengerWindow()),
          ),
        );
        await tester.pump();

        // Initially in standard mode
        expect(
          find.byKey(const ValueKey('standard_mode_view')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('compact_mode_view')), findsNothing);

        // AnimatedSwitcher is present in tree
        expect(find.byType(AnimatedSwitcher), findsWidgets);

        // Switch to compact mode
        coordinator.setCompactModeForTesting(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // Now in compact mode view
        expect(find.byKey(const ValueKey('compact_mode_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('standard_mode_view')), findsNothing);

        // Switch back to standard mode
        coordinator.setCompactModeForTesting(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(
          find.byKey(const ValueKey('standard_mode_view')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('compact_mode_view')), findsNothing);
      },
    );
  });
}
