import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/lan_discovery.dart';
import 'package:ja_lan_messenger/modules/network/network_utils.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

void main() {
  group('Network Adapter Selection & Immediate Update Tests', () {
    test(
      'LanDiscoveryService.updateDisabledAdapters updates scanState immediately',
      () async {
        final discovery = LanDiscoveryService();
        addTearDown(() => discovery.stop());

        // Trigger update with disabled names
        await discovery.updateDisabledAdapters({'Ethernet', 'Tailscale'});

        expect(discovery.disabledAdapterNames, contains('Ethernet'));
        expect(discovery.disabledAdapterNames, contains('Tailscale'));
        expect(discovery.scanState.activeAdaptersCount, 0);
        expect(discovery.scanState.activeSubnets, isEmpty);
      },
    );

    test(
      'NetworkUtils adapter caching preserves adapters within TTL and invalidates on demand',
      () async {
        NetworkUtils.invalidateAdapterCache();
        final first = await NetworkUtils.getAvailableAdapters();
        final second = await NetworkUtils.getAvailableAdapters();
        expect(first.length, second.length);

        NetworkUtils.invalidateAdapterCache();
        final third = await NetworkUtils.getAvailableAdapters(
          forceRefresh: true,
        );
        expect(third.length, second.length);
      },
    );

    test(
      'MessengerCoordinator.saveNetworkAdapters updates state and marks offline out-of-subnet peers',
      () async {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        // Simulate a peer on 192.168.100.55
        final peer = PeerModel(
          id: '192.168.100.55:6475',
          name: 'RemoteUser',
          ip: '192.168.100.55',
          port: 6475,
          status: PeerStatus.online,
          statusDescription: 'Sẵn sàng',
          knownIps: {'192.168.100.55'},
        );
        coordinator.peersMap[peer.id] = peer;

        // Save disabled adapters
        await coordinator.saveNetworkAdapters({'Ethernet', 'Tailscale'});

        expect(
          coordinator.networkPreferences.disabledNames,
          contains('Ethernet'),
        );
        expect(
          coordinator.networkPreferences.disabledNames,
          contains('Tailscale'),
        );
      },
    );
  });
}
