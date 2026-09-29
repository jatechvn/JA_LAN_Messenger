import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';

class _FakeSocket extends Fake implements Socket {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('BeeBEEP Detection Tests', () {
    test('Correctly identifies native BeeBEEP vs JA LAN Messenger', () {
      // 1. Native BeeBEEP clients (version 5.x, simple color, no JA marker)
      expect(
        ProtocolBeebeep.isRemoteBeebeep(
          version: '5.8.4',
          color: '#0000ff',
          client: '',
        ),
        isTrue,
      );
      expect(
        ProtocolBeebeep.isRemoteBeebeep(
          version: '5.8.2',
          color: '#ff5500',
          client: '',
        ),
        isTrue,
      );

      // 2. JA LAN Messenger clients (version 1.4.0, avatar preset/b64, or JA marker)
      expect(
        ProtocolBeebeep.isRemoteBeebeep(
          version: '1.4.0',
          color: '#3b82f6|preset:initials',
          client: '',
        ),
        isFalse,
      );
      expect(
        ProtocolBeebeep.isRemoteBeebeep(
          version: '1.4.0',
          color: '#3b82f6|b64:abcxyz',
          client: '',
        ),
        isFalse,
      );
      expect(
        ProtocolBeebeep.isRemoteBeebeep(
          version: '1.4.0',
          color: '#3b82f6',
          client: 'JA_LAN_MESSENGER',
        ),
        isFalse,
      );
    });
  });

  group('Peer Unification and Conversation Jumping Prevention Tests', () {
    late Directory tempDir;
    late ChatHistoryService history;
    late MessengerCoordinator coordinator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('peer_unify_test_');
      history = ChatHistoryService();
      history.setCustomDirectoryForTesting(tempDir);
      AppPreferences().setCustomFileForTesting(
        File('${tempDir.path}/prefs.json'),
      );
      await AppPreferences().load();
      MessengerCoordinator.customGroupsFileForTesting = File(
        '${tempDir.path}/groups.json',
      );
      coordinator = MessengerCoordinator(
        knownDevices: KnownDevicesRegistry('${tempDir.path}/devices.json'),
      );
      await coordinator.historyLoaded;
    });

    tearDown(() async {
      await history.flush();
      coordinator.dispose();
      history.setCustomDirectoryForTesting(null);
      AppPreferences().setCustomFileForTesting(null);
      MessengerCoordinator.customGroupsFileForTesting = null;
    });

    test(
      'Machine with uninstalled BeeBEEP (running JA Messenger) does not show Bee badge',
      () {
        // Machine 172.21.174.103 sends JA LAN Messenger handshake
        coordinator.handlePeerHandshake('172.21.174.103', {
          'username': 'Trọng Mini',
          'hostname': 'DESKTOP-7V2VRAR',
          'account': 'ft',
          'port': 6475,
          'version': '1.4.0',
          'color': '#3b82f6|preset:initials',
          'client': 'JA_LAN_MESSENGER',
        }, _FakeSocket());

        final peer = coordinator.peers.firstWhere(
          (p) => p.ip == '172.21.174.103',
        );
        expect(peer.isBeebeep, isFalse);
      },
    );

    test(
      'Multi-NIC or port-change on same station merges conversation and prevents jumping',
      () async {
        // 1. Peer connects via Ethernet IP 172.21.174.103 on port 6475
        coordinator.handlePeerHandshake('172.21.174.103', {
          'username': 'Trọng Mini',
          'hostname': 'DESKTOP-7V2VRAR',
          'account': 'ft',
          'port': 6475,
          'version': '1.4.0',
          'color': '#3b82f6|preset:initials',
          'client': 'JA_LAN_MESSENGER',
        }, _FakeSocket());

        final peer1 = coordinator.peersMap['172.21.174.103:6475']!;
        coordinator.selectPeer(peer1);
        expect(coordinator.selectedPeer, same(peer1));

        // Send a message to peer1
        await coordinator.sendMessage('Chào Trọng');
        expect(coordinator.currentMessages, hasLength(1));
        expect(coordinator.currentMessages.first.text, 'Chào Trọng');

        // 2. Now peer reconnects via WiFi/Hotspot IP 192.168.137.231 (same physical PC)
        coordinator.handlePeerHandshake('192.168.137.231', {
          'username': 'Trọng Mini',
          'hostname': 'DESKTOP-7V2VRAR',
          'account': 'ft',
          'port': 6475,
          'version': '1.4.0',
          'color': '#3b82f6|preset:initials',
          'client': 'JA_LAN_MESSENGER',
        }, _FakeSocket());

        // Sidebar list should have only 1 peer card for Trọng Mini
        final nonAiPeers = coordinator.peers
            .where((p) => !p.isAiAssistant)
            .toList();
        expect(nonAiPeers, hasLength(1));
        expect(nonAiPeers.first.name, 'Trọng Mini');

        // Selection MUST NOT jump away
        expect(coordinator.isPeerSelected(peer1), isTrue);
        expect(coordinator.selectedPeer, same(peer1));

        // 3. Incoming message arrives from 192.168.137.231
        coordinator.handleIncomingMessage(
          '192.168.137.231',
          'msg-remote-1',
          'Em nghe a ơi',
          DateTime.now(),
        );

        expect(coordinator.currentMessages, hasLength(2));
        expect(coordinator.currentMessages.last.text, 'Em nghe a ơi');
        expect(coordinator.currentMessages.last.status, MessageStatus.delivered);

        // 4. Peer also has BeeBEEP running on port 6477 or reconnects with BeeBEEP
        coordinator.handlePeerHandshake('172.21.174.103', {
          'username': 'Trọng Mini',
          'hostname': 'DESKTOP-7V2VRAR',
          'account': 'ft',
          'port': 6477,
          'version': '5.8.4',
          'color': '#ff0000',
          'client': '',
        }, _FakeSocket());

        // Still exactly 1 peer in list!
        expect(coordinator.peers.where((p) => !p.isAiAssistant), hasLength(1));
        // Selection is still firmly held!
        expect(coordinator.isPeerSelected(peer1), isTrue);
        // All messages are still intact in active chat!
        expect(coordinator.currentMessages, hasLength(2));
      },
    );

    test(
      'Startup consolidation merges multiple conversation files for the same physical host',
      () async {
        // Prepare 2 separate conversation files for the same station
        final file1 = File('${tempDir.path}\\172.21.174.103_6475.json');
        final file2 = File('${tempDir.path}\\192.168.137.231_6475.json');

        await file1.writeAsString('''{
          "version": 1,
          "conversationId": "172.21.174.103:6475",
          "lastUpdated": "2026-09-24T10:00:00.000Z",
          "messages": [
            {
              "id": "msg-1",
              "senderId": "me",
              "senderName": "FT",
              "recipientId": "172.21.174.103:6475",
              "text": "Tin từ Ethernet",
              "timestamp": "2026-09-24T10:00:00.000Z",
              "isMine": true,
              "status": "delivered"
            }
          ]
        }''');

        await file2.writeAsString('''{
          "version": 1,
          "conversationId": "192.168.137.231:6475",
          "lastUpdated": "2026-09-24T10:05:00.000Z",
          "messages": [
            {
              "id": "msg-2",
              "senderId": "me",
              "senderName": "FT",
              "recipientId": "192.168.137.231:6475",
              "text": "Tin từ WiFi",
              "timestamp": "2026-09-24T10:05:00.000Z",
              "isMine": true,
              "status": "delivered"
            }
          ]
        }''');

        // Record both IPs in knownDevices for station Trọng Mini
        coordinator.knownDevices.recordDevice(
          identityKey: 'ft@desktop-7v2vrar',
          username: 'Trọng Mini',
          ip: '172.21.174.103',
        );
        coordinator.knownDevices.recordDevice(
          identityKey: 'ft@desktop-7v2vrar',
          username: 'Trọng Mini',
          ip: '192.168.137.231',
        );

        // Load chat history
        final newCoord = MessengerCoordinator(
          knownDevices: coordinator.knownDevices,
        );
        addTearDown(newCoord.dispose);
        await newCoord.historyLoaded;

        // Verify deduplication: exactly 1 peer card in sidebar
        final peersList = newCoord.peers
            .where((p) => !p.isAiAssistant)
            .toList();
        expect(peersList, hasLength(1));

        // Select the consolidated peer
        newCoord.selectPeer(peersList.first);

        // Verify conversations were unified chronologically
        expect(newCoord.currentMessages, hasLength(2));
        expect(newCoord.currentMessages[0].text, 'Tin từ Ethernet');
        expect(newCoord.currentMessages[1].text, 'Tin từ WiFi');
      },
    );
  });
}
