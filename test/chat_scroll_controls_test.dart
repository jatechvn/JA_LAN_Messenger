import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chat Scroll Controls & Telegram-style Navigation Tests', () {
    test(
      'Localization keys for scroll controls and unread banner exist in vi, en, zh',
      () {
        final lang = LanguageProvider();
        for (final l in AppLanguage.values) {
          lang.setLanguage(l);
          expect(lang.tr('scrollToTop'), isNotEmpty);
          expect(lang.tr('scrollToBottom'), isNotEmpty);
          expect(lang.tr('newMessagesCount'), contains('%d'));
          expect(lang.tr('unreadMessagesBanner'), isNotEmpty);
        }
      },
    );

    testWidgets('Empty chat: ChatViewPanel handles zero messages gracefully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      final peer = coordinator.allUsersPeer;
      coordinator.conversationsMap[peer.id] = [];
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
      await tester.pumpAndSettle();

      // No scroll buttons should be shown for empty chats
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.text(lang.tr('unreadMessagesBanner')), findsNothing);
    });

    testWidgets(
      'ChatViewPanel displays scroll controls and reacts to scroll positions',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peer = coordinator.allUsersPeer;
        coordinator.selectPeer(peer);

        // Generate 50 read messages so the list is scrollable and starts at bottom
        final testMessages = List.generate(
          50,
          (i) => MessageModel(
            id: 'msg_$i',
            senderId: 'remote_user',
            senderName: 'Remote User',
            recipientId: peer.id,
            text:
                'Message number $i: This is a test message to fill space and enable scrolling.',
            timestamp: DateTime.now().add(Duration(seconds: i)),
            isMine: false,
            status: MessageStatus.read,
          ),
        );
        coordinator.conversationsMap[peer.id] = testMessages;

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

        // Allow frames and post frame callbacks to settle (jumping to bottom)
        await tester.pumpAndSettle();

        // At the bottom of the chat list, only the scroll to top button should be present
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);

        // Tap scroll to top
        await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
        await tester.pumpAndSettle();

        // Now at the top, only scroll to bottom button should be present
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);

        // Simulate an incoming message while at the top (scrolled up)
        final newMessage = MessageModel(
          id: 'msg_new_incoming',
          senderId: 'remote_user',
          senderName: 'Remote User',
          recipientId: peer.id,
          text: 'A brand new message arrived while looking at top!',
          timestamp: DateTime.now().add(const Duration(minutes: 1)),
          isMine: false,
          status: MessageStatus.delivered,
        );
        coordinator.conversationsMap[peer.id] = [...testMessages, newMessage];
        coordinator.notifyListeners();

        await tester.pumpAndSettle();

        // Verify new message badge appears next to scroll down button
        expect(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '1')),
          findsOneWidget,
        );

        // Tap the new message badge to scroll to bottom
        await tester.tap(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '1')),
        );
        await tester.pumpAndSettle();

        // After jumping to bottom, badge is gone and scroll to top button is back
        expect(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '1')),
          findsNothing,
        );
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      },
    );

    testWidgets(
      'Switching conversations with all messages read jumps to bottom',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peerA = coordinator.allUsersPeer;
        final peerB = PeerModel(
          id: 'peer_b',
          name: 'Peer B',
          ip: '192.168.1.50',
          port: 12345,
        );

        coordinator.conversationsMap[peerA.id] = List.generate(
          50,
          (i) => MessageModel(
            id: 'msg_a_$i',
            senderId: 'remote_a',
            senderName: 'Remote A',
            recipientId: peerA.id,
            text: 'Peer A Message $i: Testing scroll extents and layout',
            timestamp: DateTime.now().add(Duration(seconds: i)),
            isMine: false,
            status: MessageStatus.read,
          ),
        );

        coordinator.conversationsMap[peerB.id] = List.generate(
          50,
          (i) => MessageModel(
            id: 'msg_b_$i',
            senderId: 'peer_b',
            senderName: 'Peer B',
            recipientId: peerB.id,
            text: 'Peer B Message $i: Testing scroll extents and layout',
            timestamp: DateTime.now().add(Duration(seconds: i)),
            isMine: false,
            status: MessageStatus.read,
          ),
        );

        coordinator.selectPeer(peerA);

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
        await tester.pumpAndSettle();

        // In Peer A, scroll up to top
        await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
        await tester.pumpAndSettle();

        // Now at the top of Peer A
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

        // Now switch to Peer B (all read)
        coordinator.selectPeer(peerB);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));

        // In Peer B (all read), it must jump to the bottom (latest message) automatically!
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      },
    );

    testWidgets(
      'Telegram-style: Switching to conversation with unread messages anchors at first unread',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peerA = coordinator.allUsersPeer;
        final peerB = PeerModel(
          id: 'peer_b',
          name: 'Peer B',
          ip: '192.168.1.50',
          port: 12345,
        );

        // Peer A messages (all read)
        coordinator.conversationsMap[peerA.id] = List.generate(
          50,
          (i) => MessageModel(
            id: 'msg_a_$i',
            senderId: 'remote_a',
            senderName: 'Remote A',
            recipientId: peerA.id,
            text:
                'Peer A Message $i: Long text content to ensure high scroll extent',
            timestamp: DateTime.now().add(Duration(seconds: i)),
            isMine: false,
            status: MessageStatus.read,
          ),
        );

        // Peer B messages: 50 read messages and 30 unread messages (total 80 messages)
        final peerBMessages = <MessageModel>[
          ...List.generate(
            50,
            (i) => MessageModel(
              id: 'msg_b_read_$i',
              senderId: 'peer_b',
              senderName: 'Peer B',
              recipientId: 'my_id',
              text:
                  'Peer B Read Message $i: Long text content to ensure high scroll extent',
              timestamp: DateTime.now().add(Duration(seconds: i)),
              isMine: false,
              status: MessageStatus.read,
            ),
          ),
          ...List.generate(
            30,
            (i) => MessageModel(
              id: 'msg_b_unread_$i',
              senderId: 'peer_b',
              senderName: 'Peer B',
              recipientId: 'my_id',
              text:
                  'Peer B Unread Message $i: Long text content to ensure high scroll extent',
              timestamp: DateTime.now().add(Duration(seconds: 50 + i)),
              isMine: false,
              status: MessageStatus.delivered,
            ),
          ),
        ];
        coordinator.conversationsMap[peerB.id] = peerBMessages;

        // Start by viewing Peer A
        coordinator.selectPeer(peerA);

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
        await tester.pumpAndSettle();

        // Now switch to Peer B (which has 30 unread messages)
        coordinator.selectPeer(peerB);
        await tester.pumpAndSettle();

        // Verify that the Telegram-style unread separator banner is visible
        expect(find.text(lang.tr('unreadMessagesBanner')), findsOneWidget);

        // Verify the first unread message text is visible
        expect(
          find.text(
            'Peer B Unread Message 0: Long text content to ensure high scroll extent',
          ),
          findsOneWidget,
        );

        // Verify that the scroll down button is visible with badge for the 30 unread messages
        expect(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '30')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

        // Test real-time message arrival while reading unread messages:
        // A 31st unread message arrives from Peer B
        final thirtyFirstUnread = MessageModel(
          id: 'msg_b_unread_30',
          senderId: 'peer_b',
          senderName: 'Peer B',
          recipientId: 'my_id',
          text: 'Peer B Thirty First Message Arriving Live',
          timestamp: DateTime.now().add(const Duration(seconds: 90)),
          isMine: false,
          status: MessageStatus.delivered,
        );
        coordinator.conversationsMap[peerB.id] = [
          ...coordinator.conversationsMap[peerB.id]!,
          thirtyFirstUnread,
        ];
        coordinator.notifyListeners();
        await tester.pumpAndSettle();

        // Badge should update from 30 to 31 without interrupting reading position
        expect(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '31')),
          findsOneWidget,
        );

        // Tapping the scroll to bottom button / badge marks all as read and scrolls to the bottom
        await tester.tap(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '31')),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));

        // After jumping to bottom, the unread badge is gone and scroll to top button is active
        expect(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '31')),
          findsNothing,
        );
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Switching across multiple conversations preserves independent read horizons',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peerA = PeerModel(
          id: 'peer_a',
          name: 'Peer A',
          ip: '192.168.1.10',
          port: 12345,
        );
        final peerB = PeerModel(
          id: 'peer_b',
          name: 'Peer B',
          ip: '192.168.1.20',
          port: 12345,
        );
        final peerC = PeerModel(
          id: 'peer_c',
          name: 'Peer C',
          ip: '192.168.1.30',
          port: 12345,
        );

        // Peer A: 50 read, 25 unread
        coordinator.conversationsMap[peerA.id] = [
          ...List.generate(
            50,
            (i) => MessageModel(
              id: 'msg_a_r_$i',
              senderId: peerA.id,
              senderName: 'Peer A',
              recipientId: 'me',
              text:
                  'A read $i: Large text content to test multi conversation horizons',
              isMine: false,
              status: MessageStatus.read,
            ),
          ),
          ...List.generate(
            25,
            (i) => MessageModel(
              id: 'msg_a_u_$i',
              senderId: peerA.id,
              senderName: 'Peer A',
              recipientId: 'me',
              text:
                  'A unread $i: Large text content to test multi conversation horizons',
              isMine: false,
              status: MessageStatus.delivered,
            ),
          ),
        ];

        // Peer B: 50 read, 0 unread
        coordinator.conversationsMap[peerB.id] = List.generate(
          50,
          (i) => MessageModel(
            id: 'msg_b_r_$i',
            senderId: peerB.id,
            senderName: 'Peer B',
            recipientId: 'me',
            text:
                'B read $i: Large text content to test multi conversation horizons',
            isMine: false,
            status: MessageStatus.read,
          ),
        );

        // Peer C: 50 read, 20 unread
        coordinator.conversationsMap[peerC.id] = [
          ...List.generate(
            50,
            (i) => MessageModel(
              id: 'msg_c_r_$i',
              senderId: peerC.id,
              senderName: 'Peer C',
              recipientId: 'me',
              text:
                  'C read $i: Large text content to test multi conversation horizons',
              isMine: false,
              status: MessageStatus.read,
            ),
          ),
          ...List.generate(
            20,
            (i) => MessageModel(
              id: 'msg_c_u_$i',
              senderId: peerC.id,
              senderName: 'Peer C',
              recipientId: 'me',
              text:
                  'C unread $i: Large text content to test multi conversation horizons',
              isMine: false,
              status: MessageStatus.delivered,
            ),
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
            child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
          ),
        );
        await tester.pumpAndSettle();

        // Chat A opens anchored at its first unread with badge 25
        expect(find.text(lang.tr('unreadMessagesBanner')), findsOneWidget);
        expect(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '25')),
          findsOneWidget,
        );

        // Switch to Chat B (fully read)
        coordinator.selectPeer(peerB);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));

        // Chat B has no unread messages, opens at bottom
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);

        // Switch to Chat C (20 unread)
        coordinator.selectPeer(peerC);
        await tester.pumpAndSettle();

        // Chat C opens anchored at its first unread with badge 20
        expect(find.text(lang.tr('unreadMessagesBanner')), findsOneWidget);
        expect(
          find.text(lang.tr('newMessagesCount').replaceFirst('%d', '20')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Typing bubble auto-scrolls into view when peer starts typing and user is near bottom',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peer = PeerModel(
          id: 'peer_typing_test',
          name: 'Remote Peer',
          ip: '192.168.1.100',
        );
        coordinator.selectPeer(peer);

        // 40 messages to ensure the list is tall and scrollable
        final testMessages = List.generate(
          40,
          (i) => MessageModel(
            id: 'msg_typing_$i',
            senderId: peer.id,
            senderName: peer.name,
            recipientId: 'me',
            text:
                'Message $i: Testing scroll position before typing bubble appears.',
            timestamp: DateTime.now().add(Duration(seconds: i)),
            isMine: false,
            status: MessageStatus.read,
          ),
        );
        coordinator.conversationsMap[peer.id] = testMessages;

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
        await tester.pumpAndSettle();

        // Initially, no typing bubble should exist in the messages list
        expect(find.textContaining(lang.tr('typing')), findsNothing);

        // Now peer starts typing
        coordinator.setPeerTypingForTesting(peer.id, true);
        await tester.pump(); // Build frame with typing bubble added
        await tester.pump(
          const Duration(milliseconds: 350),
        ); // Advance animation frames for scroll & entry

        // Typing bubble must now be present and fully visible
        expect(find.textContaining(lang.tr('typing')), findsWidgets);
        await tester.pump(
          const Duration(milliseconds: 250),
        ); // Finish scroll ticker.
        await tester.pump();
        final typingText = find.text('Remote Peer ${lang.tr('typing')}');
        final viewport = tester.getRect(find.byType(ListView).first);
        final bubbleText = tester.getRect(typingText);
        expect(bubbleText.top, greaterThanOrEqualTo(viewport.top));
        expect(bubbleText.bottom, lessThanOrEqualTo(viewport.bottom));

        // Peer stops typing
        coordinator.setPeerTypingForTesting(peer.id, false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.textContaining(lang.tr('typing')), findsNothing);
      },
    );

    testWidgets(
      'Typing bubble does NOT auto-scroll if user is scrolled far up reading old messages',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peer = PeerModel(
          id: 'peer_typing_scroll_up_test',
          name: 'Remote Peer 2',
          ip: '192.168.1.101',
        );
        coordinator.selectPeer(peer);

        final testMessages = List.generate(
          60,
          (i) => MessageModel(
            id: 'msg_old_$i',
            senderId: peer.id,
            senderName: peer.name,
            recipientId: 'me',
            text: 'History message $i to create a long chat buffer.',
            timestamp: DateTime.now().add(Duration(seconds: i)),
            isMine: false,
            status: MessageStatus.read,
          ),
        );
        coordinator.conversationsMap[peer.id] = testMessages;

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
        await tester.pumpAndSettle();

        // Scroll up to top of history
        await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
        await tester.pumpAndSettle();

        final scrollableState = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final topOffset = scrollableState.position.pixels;
        expect(topOffset, lessThanOrEqualTo(50.0));

        // Peer starts typing
        coordinator.setPeerTypingForTesting(peer.id, true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // Position should remain at top (not auto-scrolled down)
        expect(scrollableState.position.pixels, lessThanOrEqualTo(50.0));
      },
    );
  });
}
