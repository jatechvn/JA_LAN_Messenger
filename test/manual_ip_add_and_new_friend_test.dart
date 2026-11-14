import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/peer_list_view.dart';
import 'package:ja_lan_messenger/modules/network/network_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MessengerCoordinator coordinator;

  setUp(() {
    coordinator = MessengerCoordinator();
  });

  tearDown(() {
    coordinator.dispose();
  });

  group('Manual IP and New Friend Logic Tests', () {
    test(
      'suggestedIpPrefixes returns 2-octet prefixes and defaults safely',
      () {
        final prefixes = coordinator.suggestedIpPrefixes;
        expect(prefixes, isNotEmpty);
        for (final p in prefixes) {
          // Must end with a dot and contain exactly 2 octets plus dot
          expect(p.endsWith('.'), isTrue);
          final parts = p.split('.');
          expect(parts.length, 3); // ['172', '21', '']
          expect(int.tryParse(parts[0]), isNotNull);
          expect(int.tryParse(parts[1]), isNotNull);
        }
      },
    );

    test(
      'markNewlyAddedPeer, isNewlyAddedPeer, and dismissNewlyAddedPeer work correctly',
      () {
        const peerId = '172.21.100.50:6475';
        expect(coordinator.isNewlyAddedPeer(peerId), isFalse);

        coordinator.markNewlyAddedPeer(peerId);
        expect(coordinator.isNewlyAddedPeer(peerId), isTrue);

        coordinator.dismissNewlyAddedPeer(peerId);
        expect(coordinator.isNewlyAddedPeer(peerId), isFalse);
      },
    );

    test('Newly added peer is prioritized at top of unpinned peers list', () {
      final peerA = PeerModel(
        id: '172.21.100.10:6475',
        name: 'Alice',
        ip: '172.21.100.10',
        status: PeerStatus.online,
      );
      final peerB = PeerModel(
        id: '172.21.100.20:6475',
        name: 'Bob',
        ip: '172.21.100.20',
        status: PeerStatus.online,
      );
      final peerZ = PeerModel(
        id: '172.21.100.30:6475',
        name: 'Zoe',
        ip: '172.21.100.30',
        status: PeerStatus.online,
      );

      coordinator.peersMap[peerA.id] = peerA;
      coordinator.peersMap[peerB.id] = peerB;
      coordinator.peersMap[peerZ.id] = peerZ;

      // Without new friend mark, Zoe is at bottom alphabetically (excluding AI assistant)
      var peers = coordinator.peers.where((p) => !p.isAiAssistant).toList();
      expect(peers.first.name, 'Alice');
      expect(peers.last.name, 'Zoe');

      // Now mark Zoe as newly added friend
      coordinator.markNewlyAddedPeer(peerZ.id);
      peers = coordinator.peers.where((p) => !p.isAiAssistant).toList();

      // Zoe jumps to the top of unpinned list
      expect(peers.first.name, 'Zoe');
      expect(coordinator.isNewlyAddedPeer(peerZ.id), isTrue);

      // If Alice is pinned, Alice stays above Zoe
      peerA.isPinned = true;
      peers = coordinator.peers.where((p) => !p.isAiAssistant).toList();
      expect(peers.first.name, 'Alice');
      expect(peers[1].name, 'Zoe');
    });

    test('addManualPeer handles invalid IP and own IP validations', () async {
      // 1. Invalid IP
      final invalidRes = await coordinator.addManualPeer('not-an-ip');
      expect(invalidRes.status, ManualAddStatus.invalidIp);
      expect(invalidRes.isInvalidIp, isTrue);

      final invalidRes2 = await coordinator.addManualPeer('172.21.100.');
      expect(invalidRes2.status, ManualAddStatus.invalidIp);

      // 2. Own IP
      final ownRes = await coordinator.addManualPeer(
        '127.0.0.1',
        coordinator.localTcpPort,
      );
      expect(ownRes.status, ManualAddStatus.ownIp);
      expect(ownRes.isOwnIp, isTrue);
    });

    test(
      'addManualPeer recognizes already existing peer and marks as new friend',
      () async {
        final existing = PeerModel(
          id: '172.21.50.60:6475',
          name: 'David',
          ip: '172.21.50.60',
          status: PeerStatus.online,
        );
        coordinator.peersMap[existing.id] = existing;

        final res = await coordinator.addManualPeer('172.21.50.60');
        expect(res.status, ManualAddStatus.alreadyExists);
        expect(res.isAlreadyExists, isTrue);
        expect(res.peer?.name, 'David');
        expect(coordinator.isNewlyAddedPeer(existing.id), isTrue);
      },
    );

    test('manual bridge endpoints match the exact loopback port', () async {
      final first = PeerModel(
        id: '127.0.0.1:16475',
        name: 'First host',
        ip: '127.0.0.1',
        port: 16475,
        status: PeerStatus.online,
      );
      final second = PeerModel(
        id: '127.0.0.1:16476',
        name: 'Second host',
        ip: '127.0.0.1',
        port: 16476,
        status: PeerStatus.online,
      );
      coordinator.peersMap[first.id] = first;
      coordinator.peersMap[second.id] = second;
      expect(
        (await coordinator.addManualEndpoint('127.0.0.1', 16476)).peer,
        same(second),
      );
      expect(
        (await coordinator.addManualEndpoint('127.0.0.1', 16477)).isSuccess,
        isFalse,
      );
      expect(NetworkUtils.parseIpv4Endpoint('127.0.0.1:16477', 6475), (
        ip: '127.0.0.1',
        port: 16477,
      ));
      expect(NetworkUtils.parseIpv4Endpoint('127.0.0.1', 6475), (
        ip: '127.0.0.1',
        port: 6475,
      ));
      for (final value in ['127.0.0.1:', '127.0.0.1:0', '127.0.0.1:65536']) {
        expect(NetworkUtils.parseIpv4Endpoint(value, 6475), isNull);
      }
    });

    test(
      'addOfflineManualPeer adds peer as offline and marks as new friend',
      () {
        final peer = coordinator.addOfflineManualPeer('172.21.99.99');
        expect(peer.ip, '172.21.99.99');
        expect(peer.status, PeerStatus.offline);
        expect(coordinator.isNewlyAddedPeer(peer.id), isTrue);
        expect(coordinator.peersMap.containsKey('172.21.99.99:6475'), isTrue);
      },
    );

    test('sendMessage automatically removes newly added peer badge', () async {
      final peer = PeerModel(
        id: '172.21.80.80:6475',
        name: 'Emma',
        ip: '172.21.80.80',
        status: PeerStatus.online,
      );
      coordinator.peersMap[peer.id] = peer;
      coordinator.markNewlyAddedPeer(peer.id);
      expect(coordinator.isNewlyAddedPeer(peer.id), isTrue);

      coordinator.selectPeer(peer);
      await coordinator.sendMessage('Hello Emma!');

      expect(coordinator.isNewlyAddedPeer(peer.id), isFalse);
    });
  });

  group('PeerListView and Add IP Dialog Widget Tests', () {
    testWidgets('Add IP button displays dialog with 2-octet prefill and hint', (
      tester,
    ) async {
      final lang = LanguageProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: coordinator),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(home: Scaffold(body: PeerListView())),
        ),
      );
      await tester.pump();

      // Find the add IP manual button
      final addBtn = find.byTooltip(lang.tr('addIpTooltip'));
      expect(addBtn, findsOneWidget);

      await tester.tap(addBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog should be visible
      expect(find.text(lang.tr('addIpTitle')), findsOneWidget);
      expect(find.text(lang.tr('connect')), findsOneWidget);

      // TextField should contain 2-octet prefix
      final textField = tester.widget<TextField>(find.byType(TextField).last);
      final controller = textField.controller!;
      expect(controller.text.endsWith('.'), isTrue);
      final parts = controller.text.split('.');
      expect(parts.length, 3); // 2 octets + trailing empty from dot

      // Cursor should be at the very end
      expect(controller.selection.baseOffset, controller.text.length);

      final bridgePeer = PeerModel(
        id: '127.0.0.1:16475',
        name: 'Bridge host',
        ip: '127.0.0.1',
        port: 16475,
        status: PeerStatus.online,
      );
      coordinator.peersMap[bridgePeer.id] = bridgePeer;
      final input = find.byType(TextField).last;
      await tester.enterText(input, '127.0.0.1:65536');
      await tester.tap(find.text(lang.tr('connect')));
      await tester.pump();
      expect(find.text(lang.tr('addIpInvalid')), findsOneWidget);

      await tester.enterText(input, bridgePeer.id);
      await tester.tap(find.text(lang.tr('connect')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(lang.tr('addIpTitle')), findsNothing);
      expect(coordinator.selectedPeer?.id, bridgePeer.id);
    });
  });
}
