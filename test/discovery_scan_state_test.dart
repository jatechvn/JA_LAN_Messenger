import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/network/lan_discovery.dart';

void main() {
  group('DiscoveryScanState Tests', () {
    test('Default scan state values', () {
      const state = DiscoveryScanState();
      expect(state.isSweeping, isFalse);
      expect(state.progress, 0.0);
      expect(state.activePhase, 'idle');
      expect(state.activeAdaptersCount, 0);
      expect(state.activeSubnets, isEmpty);
      expect(state.discoveredPeersCount, 0);
    });

    test('DiscoveryScanState copyWith creates accurate immutable updates', () {
      const initial = DiscoveryScanState();
      final updated = initial.copyWith(
        isSweeping: true,
        progress: 0.35,
        statusText: 'Đang phát sóng đa tầng...',
        activePhase: 'broadcasting',
        activeAdaptersCount: 2,
        activeSubnets: ['172.21.168.0/21'],
        discoveredPeersCount: 5,
      );

      expect(updated.isSweeping, isTrue);
      expect(updated.progress, 0.35);
      expect(updated.statusText, 'Đang phát sóng đa tầng...');
      expect(updated.activePhase, 'broadcasting');
      expect(updated.activeAdaptersCount, 2);
      expect(updated.activeSubnets, ['172.21.168.0/21']);
      expect(updated.discoveredPeersCount, 5);

      // Verify original is unchanged
      expect(initial.isSweeping, isFalse);
      expect(initial.progress, 0.0);
    });

    test('LanDiscoveryService initializes with default DiscoveryScanState', () {
      final service = LanDiscoveryService();
      expect(service.scanState.isSweeping, isFalse);
      expect(service.scanState.progress, 0.0);
      expect(service.isRunning, isFalse);
    });
  });
}
