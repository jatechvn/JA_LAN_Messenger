import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/lan_discovery.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'package:ja_lan_messenger/modules/network/network_utils.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'group_sync_and_ui_test.dart' show RecordingServer, UnusedSocket;

class _PolicyDiscovery extends LanDiscoveryService {
  @override
  List<NetworkInterfaceDetails> get enabledAdapters => [
    if (!disabledAdapterNames.contains('LAN-A'))
      NetworkInterfaceDetails(
        name: 'LAN-A',
        ip: '192.0.2.1',
        subnet: '192.0.2.0/24',
        isVirtual: false,
        isPrivateLan: true,
      ),
    if (!disabledAdapterNames.contains('LAN-B'))
      NetworkInterfaceDetails(
        name: 'LAN-B',
        ip: '198.51.100.1',
        subnet: '198.51.100.0/24',
        isVirtual: false,
        isPrivateLan: true,
      ),
  ];
}

class _PolicyServer extends RecordingServer {
  bool listening = false;
  int globalCloses = 0;
  final closed = <String>[];
  final probes = <String>[];
  @override
  bool get isListening => listening;
  @override
  void closeConnections() {
    globalCloses++;
  }

  @override
  void closeConnection(String endpoint) {
    closed.add(endpoint);
  }

  @override
  Future<bool> connect(
    String ip,
    int port, {
    String? sourceAddress,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    probes.add('$ip:$port');
    return false;
  }

  @override
  void sendToAll(List<int> packet) {
    send('all', packet);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MessengerCoordinator c;
  late _PolicyServer server;
  late KnownDevicesRegistry devices;
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('presence_policy_');
    AppPreferences().setCustomFileForTesting(File('${dir.path}/prefs.json'));
    await AppPreferences().load();
    ChatHistoryService().setCustomDirectoryForTesting(
      Directory('${dir.path}/history')..createSync(),
    );
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${dir.path}/groups.json',
    );
    server = _PolicyServer();
    devices = KnownDevicesRegistry('${dir.path}/devices.json');
    c = MessengerCoordinator(
      tcpServer: server,
      knownDevices: devices,
      discovery: _PolicyDiscovery(),
    );
    await c.historyLoaded;
  });
  tearDown(() async {
    c.dispose();
    await ChatHistoryService().flush();
    AppPreferences().setCustomFileForTesting(null);
    ChatHistoryService().setCustomDirectoryForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
  });
  PeerModel hello(String account, {String ip = '192.0.2.10', int port = 6475}) {
    c.handlePeerHandshake(ip, {
      'port': port,
      'username': account,
      'account': account,
      'hostname': 'shared-host',
      'status': PeerStatus.online,
      'hash': account,
      'client': 'JA_LAN_MESSENGER',
    }, UnusedSocket());
    return c.peersMap['$ip:$port']!;
  }

  test(
    'different accounts at independent ports retain presence, routing and registry IPs',
    () async {
      final alice = hello('alice');
      final bob = hello('bob', port: 6477);
      expect(alice.status, PeerStatus.online);
      expect(bob.status, PeerStatus.online);
      c.setPeerNickname(alice.id, 'Alice nickname');
      final restored = KnownDevicesRegistry('${dir.path}/devices.json');
      expect(
        restored.findByIdentity('alice@shared-host')!.knownIps,
        contains('192.0.2.10'),
      );
      expect(
        restored.findByIdentity('bob@shared-host')!.knownIps,
        contains('192.0.2.10'),
      );
      expect(
        devices.findByIdentity('alice@shared-host')!.knownIps,
        contains('192.0.2.10'),
      );
      c.handlePeerStatus('192.0.2.10:6475', {'data': '2', 'text': 'Busy'});
      expect(alice.status, PeerStatus.busy);
      expect(bob.status, PeerStatus.online);
      c.selectPeer(alice);
      await c.sendMessage('for Alice');
      expect(
        server.sent
            .where((p) => p.message['text'] == 'for Alice')
            .single
            .endpoint,
        '192.0.2.10:6475',
      );
      c.handlePeerDisconnected('192.0.2.10:6477');
      expect(alice.status, PeerStatus.busy);
      expect(bob.status, PeerStatus.offline);
    },
  );
  test(
    'status and description updates broadcast UserStatus without closing transports',
    () async {
      await c.updateProfile(status: PeerStatus.away, statusDesc: 'Break');
      expect(server.globalCloses, 0);
      final packet = server.sent.single.message;
      expect(packet['header'], ProtocolBeebeep.headerUser);
      expect(packet['flags'], 4);
      expect(packet['data'], '3');
      expect(packet['text'], 'Break');
    },
  );

  test(
    'reusing one endpoint does not evict another live port of its previous owner',
    () async {
      final alice = hello('alice');
      hello('alice', port: 6477);
      hello('bob');
      final bob = c.peers.firstWhere((p) => p.accountName == 'bob');
      expect(alice.status, PeerStatus.online);
      expect(bob.status, PeerStatus.online);
      c.handlePeerStatus('192.0.2.10:6475', {'data': '2', 'text': 'Busy'});
      expect(bob.status, PeerStatus.busy);
      expect(alice.status, PeerStatus.online);
      await c.sendMessage('Alice on remaining port', recipient: alice);
      expect(
        server.sent
            .where((p) => p.message['text'] == 'Alice on remaining port')
            .single
            .endpoint,
        '192.0.2.10:6477',
      );
    },
  );
  test(
    'all-disabled NIC policy stops presence, sends and restored-peer probing',
    () async {
      final alice = hello('alice');
      c.selectPeer(alice);
      await c.saveNetworkAdapters({'LAN-A', 'LAN-B'});
      expect(alice.status, PeerStatus.offline);
      expect(server.closed, contains('192.0.2.10:6475'));
      server.listening = true;
      await c.probeKnownAndRestoredPeersForTesting();
      await c.sendMessage('blocked');
      expect(server.probes, isEmpty);
      expect(server.sent.where((p) => p.message['text'] == 'blocked'), isEmpty);
      c.handlePeerStatus('192.0.2.10:6475', {'data': '1', 'text': ''});
      expect(alice.status, PeerStatus.offline);
    },
  );

  test(
    'disabling one NIC preserves peers and routes on the remaining NIC',
    () async {
      final alice = hello('alice');
      final bob = hello('bob', ip: '198.51.100.10');
      await c.saveNetworkAdapters({'LAN-A'});
      expect(alice.status, PeerStatus.offline);
      expect(bob.status, PeerStatus.online);
      expect(server.closed, ['192.0.2.10:6475']);
      await c.sendMessage('allowed', recipient: bob);
      expect(
        server.sent
            .where((p) => p.message['text'] == 'allowed')
            .single
            .endpoint,
        '198.51.100.10:6475',
      );
      await c.sendMessage('blocked', recipient: alice);
      expect(server.probes, isEmpty);
      expect(server.sent.where((p) => p.message['text'] == 'blocked'), isEmpty);
      await c.saveNetworkAdapters({});
      hello('alice');
      expect(alice.status, PeerStatus.online);
      expect(bob.status, PeerStatus.online);
    },
  );

  test(
    'a DNS result arriving after NICs are disabled cannot restart probing',
    () async {
      final alice = hello('alice');
      c.handlePeerDisconnected('192.0.2.10:6475');
      final entered = Completer<void>();
      final addresses = Completer<List<String>>();
      c.hostnameResolverForTesting = (_) {
        if (!entered.isCompleted) entered.complete();
        return addresses.future;
      };
      final sending = c.sendMessage('late DNS', recipient: alice);
      await entered.future;
      await c.saveNetworkAdapters({'LAN-A', 'LAN-B'});
      server.probes.clear();
      addresses.complete(['198.51.100.20']);
      await sending;
      expect(server.probes, isEmpty);
      expect(
        server.sent.where((p) => p.message['text'] == 'late DNS'),
        isEmpty,
      );
    },
  );

  test(
    'real encrypted UserStatus update keeps both TCP endpoints connected',
    () async {
      c.dispose();
      final local = LanTcpServer(), remote = LanTcpServer();
      c = MessengerCoordinator(tcpServer: local, knownDevices: devices);
      await c.historyLoaded;
      addTearDown(remote.stop);
      List<int> helloPacket(String key, LanTcpServer tcp, String account) =>
          ProtocolBeebeep.buildHelloPacket(
            localPort: tcp.port,
            username: account,
            accountName: account,
            status: PeerStatus.online,
            statusDescription: '',
            appVersion: '1.11.0',
            avatarHexColor: '#112233',
            workgroup: '',
            publicKey: key,
          );
      await local.start(port: 0);
      await remote.start(port: 0);
      local.helloBuilder = (key) => helloPacket(key, local, 'local');
      remote.helloBuilder = (key) => helloPacket(key, remote, 'remote');
      final received = Completer<Map<String, dynamic>>();
      var disconnects = 0;
      remote.onUserStatus = (_, packet) {
        if (!received.isCompleted) received.complete(packet);
      };
      remote.onDisconnected = (_) => disconnects++;
      expect(await local.connect('127.0.0.1', remote.port), isTrue);
      await c.updateProfile(status: PeerStatus.away, statusDesc: 'Break');
      expect(
        (await received.future.timeout(const Duration(seconds: 3)))['data'],
        '3',
      );
      expect(local.isConnected('127.0.0.1:${remote.port}'), isTrue);
      expect(remote.isConnected('127.0.0.1:${local.port}'), isTrue);
      expect(disconnects, 0);
    },
  );
}
