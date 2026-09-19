import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/bounce_marquee_text.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/contact_profile_dialog.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BounceMarqueeText Unit & Widget Tests', () {
    testWidgets('Renders short string without overflowing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: BounceMarqueeText(
                text: 'Short Name',
                pauseStart: Duration(milliseconds: 100),
                pauseEnd: Duration(milliseconds: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Short Name'), findsOneWidget);
    });

    testWidgets('Renders long string with BounceMarqueeText', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              child: BounceMarqueeText(
                text: 'Very Long User Display Name That Exceeds Width',
                pauseStart: Duration(milliseconds: 100),
                pauseEnd: Duration(milliseconds: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('Very Long User Display Name That Exceeds Width'),
        findsOneWidget,
      );
    });
  });

  group('ContactProfileDialog Widget Tests', () {
    testWidgets('Displays peer avatar, name, status, and IP address', (
      tester,
    ) async {
      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      final peer = PeerModel(
        id: 'peer_1',
        name: 'Minh Sang',
        ip: '192.168.1.55',
        port: 6475,
        hostname: 'DESKTOP-LAN',
        workgroup: 'OFFICE_WORKGROUP',
        status: PeerStatus.online,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => ContactProfileDialog.show(ctx, peer: peer),
                  child: const Text('Open Profile'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open Profile'));
      await tester.pumpAndSettle();

      expect(find.byType(GlassDialog), findsOneWidget);
      expect(find.text('Minh Sang'), findsOneWidget);
      expect(find.text('192.168.1.55:6475'), findsOneWidget);
      expect(find.text('DESKTOP-LAN'), findsOneWidget);
      expect(find.text('OFFICE_WORKGROUP'), findsOneWidget);

      // Close button closes dialog
      await tester.tap(find.text(lang.tr('closeDialog')));
      await tester.pumpAndSettle();
      expect(find.byType(GlassDialog), findsNothing);
    });
  });

  group('Compact Chat Header Enhanced Layout Tests', () {
    testWidgets(
      'In compact mode: Avatar has status dot, Name uses BounceMarqueeText, Nudge is hidden from Header',
      (tester) async {
        tester.view.physicalSize = const Size(340, 560);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        final peer = PeerModel(
          id: 'peer_alice',
          name: 'Alice Cooper (Senior LAN Engineer)',
          ip: '192.168.1.88',
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
            child: const MaterialApp(
              home: Scaffold(
                body: ChatViewPanel(isCompact: true),
              ),
            ),
          ),
        );
        await tester.pump();

        // 1. Name is rendered via BounceMarqueeText
        expect(find.byType(BounceMarqueeText), findsOneWidget);
        expect(find.text('Alice Cooper (Senior LAN Engineer)'), findsOneWidget);

        // 2. Nudge 🔔 icon is NOT in the Header in compact mode (Idea 5)
        // Note: The input dock below has Notifications icon, but Header only has 📌 and ↗️
        expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
        expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);

        // 3. Tapping the Header opens ContactProfileDialog (Idea 4)
        await tester.tap(find.byType(InkWell).first);
        await tester.pumpAndSettle();

        expect(find.byType(ContactProfileDialog), findsOneWidget);
        expect(find.text('192.168.1.88:6475'), findsOneWidget);

        // Close dialog
        await tester.tap(find.text(lang.tr('closeDialog')));
        await tester.pumpAndSettle();
        expect(find.byType(ContactProfileDialog), findsNothing);
      },
    );
  });
}
