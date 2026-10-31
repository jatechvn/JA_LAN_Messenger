import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

List<int> _buildTestHello({
  required String publicKey,
  required int port,
  required String username,
  required String account,
  required String hostname,
}) => ProtocolBeebeep.buildHelloPacket(
  localPort: port,
  username: username,
  status: PeerStatus.online,
  statusDescription: 'Sẵn sàng',
  accountName: account,
  appVersion: '1.11.0',
  avatarHexColor: '#3B82F6|preset:initials',
  workgroup: 'General',
  publicKey: publicKey,
  hostname: hostname,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('peer_restart_presence_');
    AppPreferences().setCustomFileForTesting(
      File('${tempDir.path}/user_preferences.json'),
    );
    ChatHistoryService().setCustomDirectoryForTesting(
      Directory('${tempDir.path}/conversations')..createSync(recursive: true),
    );
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${tempDir.path}/groups.json',
    );
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    ChatHistoryService().setCustomDirectoryForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  test(
    'LanTcpServer accepts incoming reconnect even when previous session is still marked ready and preferOutgoing is true',
    () async {
      // Bind two servers so that serverLow.port < serverHigh.port, making
      // local.compareTo(endpoint) < 0 (preferOutgoing == true) on serverLow.
      final s1 = LanTcpServer();
      final s2 = LanTcpServer();
      addTearDown(() async {
        await s1.stop();
        await s2.stop();
      });

      expect(await s1.start(port: 0), isTrue);
      expect(await s2.start(port: 0), isTrue);

      final serverLow = s1.port < s2.port ? s1 : s2;
      final serverHigh = s1.port < s2.port ? s2 : s1;

      var lowHandshakes = 0;
      serverLow.helloBuilder = (key) => _buildTestHello(
        publicKey: key,
        port: serverLow.port,
        username: 'LowPeer',
        account: 'low',
        hostname: 'PC-LOW',
      );
      serverHigh.helloBuilder = (key) => _buildTestHello(
        publicKey: key,
        port: serverHigh.port,
        username: 'HighPeer',
        account: 'high',
        hostname: 'PC-HIGH',
      );
      serverLow.onHandshake = (_, _, _) {
        lowHandshakes++;
      };

      // 1. serverLow connects outgoing to serverHigh (so previous.isOutgoing == true on serverLow)
      expect(
        await serverLow.connect('127.0.0.1', serverHigh.port),
        isTrue,
      );
      expect(lowHandshakes, 1);

      // 2. Simulate HighPeer restarting its app and immediately initiating a new
      // connection to serverLow while serverLow's old session is still open/ready.
      final reconnected = LanTcpServer();
      addTearDown(reconnected.stop);
      reconnected.helloBuilder = (key) => _buildTestHello(
        publicKey: key,
        port: serverHigh.port,
        username: 'HighPeer',
        account: 'high',
        hostname: 'PC-HIGH',
      );
      expect(await reconnected.start(port: 0), isTrue);

      // Wait 5ms so attachedAt of the new socket is strictly after previous.connectedAt
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final ok = await reconnected.connect('127.0.0.1', serverLow.port);
      expect(
        ok,
        isTrue,
        reason:
            'Reconnect from restarted peer must replace stale session instead of being rejected with duplicate_rejected',
      );
      expect(lowHandshakes, 2);
      expect(
        serverLow.isConnected('127.0.0.1:${serverHigh.port}'),
        isTrue,
      );
    },
  );

  test(
    'Startup probeKnownAndRestoredPeers immediately brings online colleagues from offline to online without pressing Buzz',
    () async {
      // Start a remote colleague's TCP server
      final remoteServer = LanTcpServer();
      addTearDown(remoteServer.stop);
      expect(await remoteServer.start(port: 0), isTrue);
      remoteServer.helloBuilder = (key) => _buildTestHello(
        publicKey: key,
        port: remoteServer.port,
        username: 'Colleague Online',
        account: 'colleague01',
        hostname: 'PC-COLLEAGUE-01',
      );

      // Seed chat history & knownDevices as if we chatted before closing our app
      final savedConvId = '127.0.0.1:${remoteServer.port}';
      await ChatHistoryService().saveImmediately(savedConvId, [
        MessageModel(
          id: 'msg-1',
          senderId: savedConvId,
          senderName: 'Colleague Online',
          recipientId: 'me',
          text: 'Hello before restart',
          isMine: false,
          status: MessageStatus.read,
        ),
      ]);

      final knownRegistry = KnownDevicesRegistry(
        '${tempDir.path}/known_devices.json',
      );
      knownRegistry.recordDevice(
        identityKey: 'colleague01@pc-colleague-01',
        username: 'Colleague Online',
        ip: '127.0.0.1',
        port: remoteServer.port,
        accountName: 'colleague01',
        hostname: 'PC-COLLEAGUE-01',
      );

      final localServer = LanTcpServer();
      final coordinator = MessengerCoordinator(
        tcpServer: localServer,
        knownDevices: knownRegistry,
      );
      addTearDown(() async {
        coordinator.dispose();
        await localServer.stop();
      });

      await coordinator.historyLoaded;
      final restoredBefore = coordinator.peers
          .where((p) => !p.isAiAssistant)
          .single;
      // Initially restored from disk as offline
      expect(restoredBefore.status, PeerStatus.offline);

      // Start local TCP server and run startup probe (simulating app reopen)
      localServer.helloBuilder = (key) => _buildTestHello(
        publicKey: key,
        port: localServer.port,
        username: 'Local User',
        account: 'local01',
        hostname: 'PC-LOCAL-01',
      );
      expect(await localServer.start(port: 0), isTrue);

      await coordinator.probeKnownAndRestoredPeersForTesting();

      // Colleague is now online immediately without needing to press Buzz!
      final colleagueAfter = coordinator.peers
          .where((p) => !p.isAiAssistant)
          .single;
      expect(colleagueAfter.status, PeerStatus.online);
      expect(colleagueAfter.name, 'Colleague Online');
    },
  );

  test(
    'Early handshake before chatHistory finishes loading preserves online status after consolidation',
    () async {
      final legacyConvId = 'peer_legacy_colleague';
      await ChatHistoryService().saveImmediately(legacyConvId, [
        MessageModel(
          id: 'm1',
          senderId: legacyConvId,
          senderName: 'Alice',
          recipientId: 'me',
          text: 'Old history message',
          isMine: false,
          status: MessageStatus.read,
        ),
      ]);

      final knownRegistry = KnownDevicesRegistry(
        '${tempDir.path}/known_devices_race.json',
      );
      knownRegistry.recordDevice(
        identityKey: 'alice@pc-alice',
        username: 'Alice',
        ip: '10.81.141.88',
        port: 6475,
        accountName: 'alice',
        hostname: 'PC-ALICE',
      );

      final coordinator = MessengerCoordinator(knownDevices: knownRegistry);
      addTearDown(coordinator.dispose);

      // Simulate handshake arriving BEFORE historyLoaded completes
      final serverSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(serverSocket.close);
      final clientSocket = await Socket.connect(
        '127.0.0.1',
        serverSocket.port,
      );
      addTearDown(clientSocket.destroy);

      coordinator.handlePeerHandshake(
        '10.81.141.88',
        {
          'port': 6475,
          'username': 'Alice',
          'status': PeerStatus.online,
          'statusDescription': 'Online',
          'account': 'alice',
          'hostname': 'PC-ALICE',
          'hash': 'hash_alice_123',
          'version': '1.11.0',
          'color': '#3B82F6|preset:initials',
          'workgroup': 'General',
          'client': 'JA_LAN_MESSENGER',
        },
        clientSocket,
      );

      await coordinator.historyLoaded;

      final alicePeers = coordinator.peers
          .where((p) => p.hostname?.toLowerCase() == 'pc-alice')
          .toList();
      expect(alicePeers.length, 1);
      expect(
        alicePeers.single.status,
        PeerStatus.online,
        reason:
            'History consolidation must not overwrite an active online session with offline',
      );
    },
  );
}
