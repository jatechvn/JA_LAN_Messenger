import 'dart:convert';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
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
import 'package:ja_lan_messenger/modules/ui/widgets/peer_list_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Localization Staged Attachments Tests', () {
    test('All staged attachment keys exist across vi, en, zh', () {
      final lang = LanguageProvider();
      const keys = [
        'attachedFiles',
        'stagedFilesCount',
        'removeAttachment',
        'clearAllAttachments',
      ];

      for (final code in ['vi', 'en', 'zh']) {
        lang.setLanguage(AppLanguage.fromCode(code));
        for (final key in keys) {
          final translated = lang.tr(key);
          expect(
            translated,
            isNot(equals(key)),
            reason: 'Key "$key" should exist in "$code"',
          );
        }

        final formatted = lang.tr('stagedFilesCount', [3]);
        expect(formatted, contains('3'));
      }
    });
  });

  group('MessengerCoordinator sendFile and sendFiles with Captions', () {
    late Directory tempDir;
    late File prefFile;
    late ChatHistoryService history;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('staged_test_');
      prefFile = File('${tempDir.path}\\prefs.json');
      AppPreferences().setCustomFileForTesting(prefFile);
      history = ChatHistoryService();
      history.setCustomDirectoryForTesting(tempDir);
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      history.setCustomDirectoryForTesting(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'sendFile with caption attaches caption text to message (AI chat)',
      () async {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final aiPeer = coordinator.peers.firstWhere((p) => p.isAiAssistant);
        coordinator.selectPeer(aiPeer);

        final dummyFile = File('${tempDir.path}\\test_document.pdf');
        await dummyFile.writeAsString('Dummy PDF content');

        await coordinator.sendFile(dummyFile, caption: 'Báo cáo tháng 9');

        final msgs = coordinator.conversationsMap[aiPeer.id];
        expect(msgs, isNotNull);
        final myMsgs = msgs!.where((m) => m.isMine).toList();
        expect(myMsgs.length, equals(1));
        final fileMsg = myMsgs.first;
        expect(fileMsg.text, equals('Báo cáo tháng 9'));
        expect(fileMsg.fileAttachment, isNotNull);
        expect(fileMsg.fileAttachment!.fileName, equals('test_document.pdf'));
        expect(aiPeer.lastMessage, equals('Báo cáo tháng 9'));
      },
    );

    test(
      'sendFiles with multiple files and caption distributes messages (AI chat)',
      () async {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final aiPeer = coordinator.peers.firstWhere((p) => p.isAiAssistant);
        coordinator.selectPeer(aiPeer);

        final file1 = File('${tempDir.path}\\photo1.png');
        await file1.writeAsString('image 1 data');
        final file2 = File('${tempDir.path}\\photo2.png');
        await file2.writeAsString('image 2 data');

        await coordinator.sendFiles([
          file1,
          file2,
        ], text: 'Hai ảnh chụp màn hình cần xem');

        final msgs = coordinator.conversationsMap[aiPeer.id];
        expect(msgs, isNotNull);
        final myMsgs = msgs!.where((m) => m.isMine).toList();
        expect(myMsgs.length, equals(2));
        // First file carries caption text
        expect(myMsgs.first.text, equals('Hai ảnh chụp màn hình cần xem'));
        expect(myMsgs.first.fileAttachment!.fileName, equals('photo1.png'));
        expect(myMsgs.last.fileAttachment!.fileName, equals('photo2.png'));
        expect(aiPeer.lastMessage, equals('Hai ảnh chụp màn hình cần xem'));
      },
    );

    test('getClipboardAttachments handles empty/null safely', () async {
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      final attachments = await coordinator.getClipboardAttachments();
      expect(attachments, isA<List<File>>());
    });
  });

  group('Scan Button Relocation and Search Header UI Tests', () {
    testWidgets(
      'Search header does not contain rescan button, scan banner contains scan button and no online count pill',
      (tester) async {
        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
              ChangeNotifierProvider.value(value: coordinator),
            ],
            child: const MaterialApp(home: Scaffold(body: PeerListView())),
          ),
        );
        await tester.pump();

        // 1. In search bar area: group_add and person_add exist, but refresh_rounded is not there
        expect(find.byIcon(Icons.group_add_rounded), findsOneWidget);
        expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);

        // 2. Refresh icon is now inside the scan banner
        expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

        // 3. Online count pill is removed from the scan banner
        // Searching for devicesOnline text should find nothing
        expect(find.textContaining(lang.tr('devicesOnline')), findsNothing);

        // 4. Tap the scan button and advance fake timers
        await tester.tap(find.byIcon(Icons.refresh_rounded));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });

  group('Chat View Panel Staged Attachments UI Tests', () {
    testWidgets('ChatViewPanel displays input dock and attach button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      final peer = PeerModel(
        id: '192.168.1.60:6475',
        name: 'TrọngMini',
        ip: '192.168.1.60',
        port: 6475,
        status: PeerStatus.online,
      );
      coordinator.peersMap[peer.id] = peer;
      coordinator.selectPeer(peer);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
        ),
      );
      await tester.pump();

      // Find attach file button (paperclip)
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      // Find send button
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);

      // Verify text input exists
      expect(find.byType(TextField), findsOneWidget);
      final dir = Directory.systemTemp.createTempSync('drop_stage_');
      final file = File('${dir.path}${Platform.pathSeparator}dropped.txt')
        ..writeAsStringSync('draft');
      final target = tester.widget<DropTarget>(find.byType(DropTarget));
      await tester.runAsync(() async {
        target.onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(file.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('dropped.txt'), findsOneWidget);
      expect(coordinator.currentMessages, isEmpty);
    });

    testWidgets(
      'StagedAttachmentsBar renders thumbnails, handles item removal and clear all',
      (tester) async {
        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final dir = Directory.systemTemp.createTempSync('staged_ui_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final imgFile = File('${dir.path}\\sample_screenshot.png');
        imgFile.writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
          ),
        );
        final docFile = File('${dir.path}\\sample_document.docx');
        docFile.writeAsStringSync('fake docx');

        int? removedIndex;
        bool cleared = false;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    return StagedAttachmentsBar(
                      files: [imgFile, docFile],
                      onRemove: (idx) => removedIndex = idx,
                      onClear: () => cleared = true,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Staged count is shown
        expect(find.text(lang.tr('stagedFilesCount', [2])), findsOneWidget);

        // Filename is shown
        expect(find.text('sample_document.docx'), findsOneWidget);

        // Clear all button exists when files > 1
        expect(find.text(lang.tr('clearAllAttachments')), findsOneWidget);
        await tester.tap(find.text(lang.tr('clearAllAttachments')));
        await tester.pump();
        expect(cleared, isTrue);

        // Remove button (close icon) on items
        final closeButtons = find.byIcon(Icons.close_rounded);
        expect(closeButtons, findsNWidgets(2));
        await tester.tap(closeButtons.first);
        await tester.pump();
        expect(removedIndex, equals(0));
      },
    );
  });
}
