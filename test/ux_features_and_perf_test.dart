import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/folder_archive_helper.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/compact_messenger_view.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/forward_message_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File prefFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ux_features_test_');
    prefFile = File('${tempDir.path}/user_preferences.json');
    AppPreferences().setCustomFileForTesting(prefFile);
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Localization Keys for New UX & Features', () {
    test('All new localization keys exist in vi, en, zh', () {
      final lang = LanguageProvider();
      const keys = [
        'searchInChat',
        'searchMessagesHint',
        'noSearchResults',
        'prevMatch',
        'nextMatch',
        'today',
        'yesterday',
        'draftPrefix',
        'forwardMessage',
        'forwardTitle',
        'forwardSearchHint',
        'forwardNoteHint',
        'forwardAction',
        'forwardSuccess',
        'zippingFolder',
        'folderZippedReady',
        'folderZipFailed',
      ];

      for (final locale in AppLanguage.values) {
        lang.setLanguage(locale);
        for (final key in keys) {
          final translated = lang.tr(key);
          expect(
            translated,
            isNotEmpty,
            reason: 'Missing or empty key "$key" for $locale',
          );
          expect(
            translated,
            isNot(equals(key)),
            reason: 'Untranslated fallback returned for "$key" in $locale',
          );
        }
      }
    });
  });

  group('MessengerCoordinator Performance & UX State Tests (P1, F2, U3)', () {
    test('Per-peer drafts are saved, retrieved, and cleared', () {
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      expect(coordinator.hasDraft('peer_1'), isFalse);
      expect(coordinator.getDraft('peer_1'), isEmpty);

      coordinator.setDraft('peer_1', 'Xin chào đồng nghiệp');
      expect(coordinator.hasDraft('peer_1'), isTrue);
      expect(coordinator.getDraft('peer_1'), equals('Xin chào đồng nghiệp'));

      // Whitespace-only is not considered an active draft, and empty string clears it
      coordinator.setDraft('peer_1', '   ');
      expect(coordinator.hasDraft('peer_1'), isFalse);
      coordinator.setDraft('peer_1', '');
      expect(coordinator.getDraft('peer_1'), isEmpty);
    });

    test('Shortcut focus request counters increment properly', () {
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      final initialSidebarId = coordinator.sidebarSearchFocusRequestId;
      final initialChatId = coordinator.chatSearchFocusRequestId;

      coordinator.requestSidebarSearchFocus();
      expect(
        coordinator.sidebarSearchFocusRequestId,
        equals(initialSidebarId + 1),
      );

      coordinator.requestChatSearchFocus();
      expect(coordinator.chatSearchFocusRequestId, equals(initialChatId + 1));
    });

    test(
      'selectAdjacentPeer navigates up and down through conversation list',
      () {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peerA = PeerModel(
          id: 'peer_a',
          name: 'Alice',
          ip: '192.168.1.10',
          status: PeerStatus.online,
        );
        final peerB = PeerModel(
          id: 'peer_b',
          name: 'Bob',
          ip: '192.168.1.20',
          status: PeerStatus.online,
        );
        coordinator.peersMap[peerA.id] = peerA;
        coordinator.peersMap[peerB.id] = peerB;

        coordinator.selectPeer(coordinator.allUsersPeer);
        expect(
          coordinator.selectedPeer?.id,
          equals(coordinator.allUsersPeer.id),
        );

        coordinator.selectAdjacentPeer(1);
        expect(
          coordinator.selectedPeer?.id,
          isNot(equals(coordinator.allUsersPeer.id)),
        );
        final firstMovedId = coordinator.selectedPeer?.id;

        coordinator.selectAdjacentPeer(-1);
        expect(
          coordinator.selectedPeer?.id,
          equals(coordinator.allUsersPeer.id),
        );

        coordinator.selectAdjacentPeer(1);
        expect(coordinator.selectedPeer?.id, equals(firstMovedId));
      },
    );
  });

  group('FolderArchiveHelper Auto-Zip Tests (F3)', () {
    test(
      'Compresses a directory into a valid non-empty .zip archive',
      () async {
        final sampleFolder = Directory('${tempDir.path}/ProjectReport');
        await sampleFolder.create(recursive: true);
        final sampleFile = File('${sampleFolder.path}/summary.txt');
        await sampleFile.writeAsString(
          'JA LAN Messenger Auto-Zip Test Content',
        );

        final zipPath = await FolderArchiveHelper.zipDirectory(
          sampleFolder.path,
          outputDir: tempDir,
        );
        expect(zipPath, isNotNull);
        if (zipPath != null) {
          final zipFile = File(zipPath);
          expect(await zipFile.exists(), isTrue);
          expect(await zipFile.length(), greaterThan(0));
        }
      },
    );
  });

  group(
    'ChatViewPanel 320px Compact Dock, Date Separators & In-Chat Search (U1, U2, F1)',
    () {
      testWidgets(
        'Renders at 320px without overflow, shows Date Separators and In-Chat Search Bar',
        (tester) async {
          tester.view.physicalSize = const Size(320, 520);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          final theme = ThemeProvider();
          final lang = LanguageProvider();
          final coordinator = MessengerCoordinator();
          addTearDown(() => coordinator.dispose());

          final peerA = PeerModel(
            id: 'peer_a',
            name: 'Alice',
            ip: '192.168.1.10',
            status: PeerStatus.online,
          );
          coordinator.peersMap[peerA.id] = peerA;

          final now = DateTime.now();
          final yesterday = now.subtract(const Duration(days: 1));
          coordinator.conversationsMap[peerA.id] = [
            MessageModel(
              id: 'msg_1',
              senderId: peerA.id,
              senderName: 'Alice',
              recipientId: 'me',
              text: 'Báo cáo ngày hôm qua',
              timestamp: yesterday,
              isMine: false,
            ),
            MessageModel(
              id: 'msg_2',
              senderId: peerA.id,
              senderName: 'Alice',
              recipientId: 'me',
              text: 'Tin nhắn đầu hôm nay',
              timestamp: now.subtract(const Duration(minutes: 2)),
              isMine: false,
            ),
            MessageModel(
              id: 'msg_3',
              senderId: peerA.id,
              senderName: 'Alice',
              recipientId: 'me',
              text: 'Tin nhắn liên tiếp cùng người gửi',
              timestamp: now.subtract(const Duration(minutes: 1)),
              isMine: false,
            ),
          ];

          coordinator.selectPeer(peerA);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: theme),
                ChangeNotifierProvider.value(value: lang),
                ChangeNotifierProvider.value(value: coordinator),
              ],
              child: const MaterialApp(
                home: Scaffold(body: ChatViewPanel(isCompact: true)),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Date separators for Today and Yesterday are rendered
          expect(find.text(lang.tr('today')), findsOneWidget);
          expect(find.text(lang.tr('yesterday')), findsOneWidget);

          // Open In-Chat Search via coordinator request (Ctrl+F equivalent)
          coordinator.requestChatSearchFocus();
          await tester.pumpAndSettle();

          // Search input hint is visible
          expect(find.text(lang.tr('searchMessagesHint')), findsOneWidget);

          // Enter query matching 'hôm qua'
          final searchFields = find.byType(TextField);
          await tester.enterText(searchFields.first, 'hôm qua');
          await tester.pumpAndSettle();

          expect(find.text('1/1'), findsOneWidget);

          // Press Escape to dismiss in-chat search
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();

          expect(find.text(lang.tr('searchMessagesHint')), findsNothing);
        },
      );
    },
  );

  group(
    'CompactMessengerView Draft Badge & ForwardMessageDialog Tests (F2, F4)',
    () {
      testWidgets(
        'Displays [Nháp] prefix in CompactMessengerView when peer has draft',
        (tester) async {
          tester.view.physicalSize = const Size(340, 560);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          final theme = ThemeProvider();
          final lang = LanguageProvider();
          final coordinator = MessengerCoordinator();
          addTearDown(() => coordinator.dispose());

          final peerA = PeerModel(
            id: 'peer_a',
            name: 'Alice',
            ip: '192.168.1.10',
            status: PeerStatus.online,
          );
          coordinator.peersMap[peerA.id] = peerA;
          coordinator.setDraft(peerA.id, 'Đang soạn dở...');
          coordinator.selectPeer(null);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: theme),
                ChangeNotifierProvider.value(value: lang),
                ChangeNotifierProvider.value(value: coordinator),
              ],
              child: const MaterialApp(
                home: Scaffold(body: CompactMessengerView()),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.textContaining('${lang.tr('draftPrefix')} Đang soạn dở...'),
            findsOneWidget,
          );
        },
      );

      testWidgets('ForwardMessageDialog allows selecting recipients', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 650);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peerA = PeerModel(
          id: 'peer_a',
          name: 'Alice',
          ip: '192.168.1.10',
          status: PeerStatus.online,
        );
        final peerB = PeerModel(
          id: 'peer_b',
          name: 'Bob',
          ip: '192.168.1.20',
          status: PeerStatus.online,
        );
        coordinator.peersMap[peerA.id] = peerA;
        coordinator.peersMap[peerB.id] = peerB;

        final sampleMsg = MessageModel(
          id: 'msg_forward_1',
          senderId: peerA.id,
          senderName: 'Alice',
          recipientId: 'me',
          text: 'Tài liệu kỹ thuật cần chuyển tiếp',
          timestamp: DateTime.now(),
          isMine: false,
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
              ChangeNotifierProvider.value(value: coordinator),
            ],
            child: MaterialApp(
              home: Scaffold(body: ForwardMessageDialog(message: sampleMsg)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(lang.tr('forwardTitle')), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);

        // Select Bob
        await tester.tap(find.text('Bob'));
        await tester.pumpAndSettle();

        expect(find.text('${lang.tr('forwardAction')} (1)'), findsOneWidget);
      });
    },
  );
}
