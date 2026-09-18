import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testFilePath;
  late KnownDevicesRegistry registry;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('known_devices_test_');
    testFilePath = '${tempDir.path}\\test_known_devices.json';
    registry = KnownDevicesRegistry(testFilePath);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('KnownDevicesRegistry Tests', () {
    test('First time recordDevice returns true, subsequent returns false', () {
      expect(registry.isDeviceKnown('ft@cmdl09'), isFalse);

      final isFirst = registry.recordDevice(
        identityKey: 'ft@cmdl09',
        username: 'FT',
        ip: '192.168.10.15',
      );
      expect(isFirst, isTrue);
      expect(registry.isDeviceKnown('ft@cmdl09'), isTrue);

      final isSecond = registry.recordDevice(
        identityKey: 'ft@cmdl09',
        username: 'FT',
        ip: '192.168.10.15',
      );
      expect(isSecond, isFalse);
    });

    test('Multi-NIC device accumulates knownIps and persists', () {
      registry.recordDevice(
        identityKey: 'cmdl09',
        username: 'CMDL09',
        ip: '192.168.10.15',
      );

      // Same device seen on a secondary NIC (e.g., Hyper-V/Wi-Fi: 172.21.175.40)
      final isSecond = registry.recordDevice(
        identityKey: 'cmdl09',
        username: 'CMDL09',
        ip: '172.21.175.40',
      );
      expect(isSecond, isFalse); // Already known!

      final device = registry.devices['cmdl09'];
      expect(device, isNotNull);
      expect(device!.knownIps.contains('192.168.10.15'), isTrue);
      expect(device.knownIps.contains('172.21.175.40'), isTrue);
      expect(device.lastIp, equals('172.21.175.40'));

      // Verify persistence by loading into a new instance
      final reloadedRegistry = KnownDevicesRegistry(testFilePath);
      expect(reloadedRegistry.isDeviceKnown('cmdl09'), isTrue);
      final reloadedDevice = reloadedRegistry.devices['cmdl09'];
      expect(reloadedDevice, isNotNull);
      expect(reloadedDevice!.knownIps.length, equals(2));
    });

    test(
      'PeerModel canonicalIdentity distinguishes stations with same Windows account',
      () {
        // CMDL01, CMDL05, CMDL09 all have Windows account "FT"
        final peer1 = PeerModel(
          id: '172.21.169.64:6475',
          name: 'CMDL01',
          ip: '172.21.169.64',
          accountName: 'FT',
          hostname: 'CMDL01',
        );

        final peer5 = PeerModel(
          id: '172.21.174.64:6475',
          name: 'CMDL05',
          ip: '172.21.174.64',
          accountName: 'FT',
          hostname: 'CMDL05',
        );

        final peer9Nic1 = PeerModel(
          id: '192.168.10.15:6475',
          name: 'CMDL09',
          ip: '192.168.10.15',
          accountName: 'FT',
          hostname: 'CMDL09',
        );

        final peer9Nic2 = PeerModel(
          id: '172.21.175.40:6475',
          name: 'CMDL09',
          ip: '172.21.175.40',
          accountName: 'FT',
          hostname: 'CMDL09',
        );

        final anon1 = PeerModel(
          id: '172.21.174.152:6475',
          name: '???',
          ip: '172.21.174.152',
          accountName: 'FT',
        );

        final anon2 = PeerModel(
          id: '172.21.174.146:6475',
          name: '???',
          ip: '172.21.174.146',
          accountName: 'FT',
        );

        // Verify canonical identities
        expect(peer1.canonicalIdentity, equals('ft@cmdl01'));
        expect(peer5.canonicalIdentity, equals('ft@cmdl05'));
        expect(peer9Nic1.canonicalIdentity, equals('ft@cmdl09'));
        expect(
          peer9Nic2.canonicalIdentity,
          equals('ft@cmdl09'),
        ); // Same machine!
        expect(anon1.canonicalIdentity, equals('172.21.174.152:6475'));
        expect(anon2.canonicalIdentity, equals('172.21.174.146:6475'));

        // Check that distinct stations NEVER have the same identity
        expect(peer1.canonicalIdentity, isNot(equals(peer5.canonicalIdentity)));
        expect(
          peer1.canonicalIdentity,
          isNot(equals(peer9Nic1.canonicalIdentity)),
        );
        expect(
          peer5.canonicalIdentity,
          isNot(equals(peer9Nic1.canonicalIdentity)),
        );
        expect(anon1.canonicalIdentity, isNot(equals(anon2.canonicalIdentity)));

        // And multi-NIC of CMDL09 matches exactly
        expect(
          peer9Nic1.canonicalIdentity,
          equals(peer9Nic2.canonicalIdentity),
        );
      },
    );
  });
}
