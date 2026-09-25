import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';

class _UnusedSocket extends Fake implements Socket {}

void main() {
  test(
    'Two NICs share a peer and chat; other hosts and sessions stay separate',
    () async {
      final history = ChatHistoryService();
      history.setCustomDirectoryForTesting(
        await Directory.systemTemp.createTemp('multi_nic_'),
      );
      final coordinator = MessengerCoordinator();
      addTearDown(() {
        coordinator.dispose();
        history.setCustomDirectoryForTesting(null);
      });
      void hello(String ip, String host, {int port = 6475}) {
        coordinator.handlePeerHandshake(ip, {
          'username': 'Same display name',
          'hostname': host,
          'account': 'user',
          'port': port,
        }, _UnusedSocket());
      }

      hello('192.0.2.1', 'PC-A');
      final first = coordinator.peersMap['192.0.2.1:6475']!;
      coordinator.selectPeer(first);
      hello('198.51.100.1', 'pc-a');
      expect(coordinator.peersMap['198.51.100.1:6475'], same(first));
      expect(first.knownIps, containsAll(['192.0.2.1', '198.51.100.1']));
      expect(coordinator.selectedPeer, same(first));
      expect(coordinator.peers.where((p) => !p.isAiAssistant), hasLength(1));
      hello('192.0.2.2', 'PC-B');
      hello('198.51.100.2', 'PC-B');
      expect(coordinator.peers.where((p) => !p.isAiAssistant), hasLength(2));
      hello('192.0.2.1', 'PC-A', port: 6477);
      // Cùng một máy vật lý dù đổi cổng (ví dụ 6475 BeeBEEP vs 6477 JA) vẫn gộp thành 1 peer duy nhất
      expect(coordinator.peers.where((p) => !p.isAiAssistant), hasLength(2));
      expect(coordinator.selectedPeer, same(first));
      expect(coordinator.peersMap['192.0.2.1:6477'], same(first));
    },
  );
}
