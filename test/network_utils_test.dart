import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/network/network_utils.dart';

void main() {
  group('NetworkUtils Tests', () {
    test('Virtual Adapter Detection', () {
      expect(
        NetworkUtils.isVirtualAdapter('Tailscale', '100.114.185.99'),
        isTrue,
      );
      expect(
        NetworkUtils.isVirtualAdapter('vEthernet (WSL)', '172.28.16.1'),
        isTrue,
      );
      expect(NetworkUtils.isVirtualAdapter('Docker', '172.17.0.1'), isTrue);
      expect(NetworkUtils.isVirtualAdapter('Loopback', '127.0.0.1'), isTrue);
      expect(
        NetworkUtils.isVirtualAdapter('Ethernet', '192.168.100.231'),
        isFalse,
      );
      expect(
        NetworkUtils.isVirtualAdapter('Ethernet 2', '172.21.175.40'),
        isFalse,
      );
    });

    test('Private LAN IP Detection', () {
      expect(NetworkUtils.isPrivateLanIp('192.168.1.5'), isTrue);
      expect(NetworkUtils.isPrivateLanIp('10.0.0.1'), isTrue);
      expect(NetworkUtils.isPrivateLanIp('172.21.175.40'), isTrue);
      expect(NetworkUtils.isPrivateLanIp('8.8.8.8'), isFalse);
      expect(NetworkUtils.isPrivateLanIp('1.1.1.1'), isFalse);
    });

    test('Netmask to Prefix Length', () {
      expect(NetworkUtils.maskToPrefixLength('255.255.255.0'), 24);
      expect(NetworkUtils.maskToPrefixLength('255.255.248.0'), 21);
      expect(NetworkUtils.maskToPrefixLength('255.255.0.0'), 16);
      expect(NetworkUtils.maskToPrefixLength('255.0.0.0'), 8);
    });

    test('CIDR Subnet Calculation', () {
      // 172.21.175.40 with 255.255.248.0 -> 172.21.168.0/21
      expect(
        NetworkUtils.calculateCidrSubnet('172.21.175.40', '255.255.248.0'),
        '172.21.168.0/21',
      );
      // Default /24
      expect(
        NetworkUtils.calculateCidrSubnet('192.168.100.231', '255.255.255.0'),
        '192.168.100.0/24',
      );
    });

    test('Subnet Slicing for Supernet (/21 -> 8 slices of /24)', () {
      final slices = NetworkUtils.getSubnetSlices('172.21.168.0/21');
      expect(slices.length, 8);
      expect(slices[0], '172.21.168.0/24');
      expect(slices[1], '172.21.169.0/24');
      expect(slices[2], '172.21.170.0/24');
      expect(slices[3], '172.21.171.0/24');
      expect(slices[4], '172.21.172.0/24');
      expect(slices[5], '172.21.173.0/24');
      expect(slices[6], '172.21.174.0/24');
      expect(slices[7], '172.21.175.0/24');
    });

    test('Directed Broadcast Calculation', () {
      expect(NetworkUtils.getBroadcastIp('192.168.100.231'), '192.168.100.255');
      expect(NetworkUtils.getBroadcastIp('172.21.170.0/24'), '172.21.170.255');
      expect(
        NetworkUtils.getSupernetBroadcastIp('172.21.175.40', '255.255.248.0'),
        '172.21.175.255',
      );
    });

    test('IP in Subnet and Local Adapter Matching', () {
      expect(
        NetworkUtils.isIpInSubnet('172.21.170.16', '172.21.168.0/21'),
        isTrue,
      );
      expect(
        NetworkUtils.isIpInSubnet('172.21.175.40', '172.21.168.0/21'),
        isTrue,
      );
      expect(
        NetworkUtils.isIpInSubnet('192.168.100.5', '172.21.168.0/21'),
        isFalse,
      );

      const adapters = [
        NetworkInterfaceDetails(
          name: 'Ethernet',
          ip: '192.168.100.231',
          subnet: '192.168.100.0/24',
          isVirtual: false,
          isPrivateLan: true,
        ),
        NetworkInterfaceDetails(
          name: 'Ethernet 2',
          ip: '172.21.175.40',
          subnet: '172.21.168.0/21',
          isVirtual: false,
          isPrivateLan: true,
        ),
      ];

      // Connecting to 172.21.170.16 should pick Ethernet 2 (172.21.175.40)
      final match1 = NetworkUtils.findMatchingLocalIp(
        '172.21.170.16',
        adapters,
      );
      expect(match1, '172.21.175.40');

      // Connecting to 192.168.100.1 should pick Ethernet (192.168.100.231)
      final match2 = NetworkUtils.findMatchingLocalIp(
        '192.168.100.1',
        adapters,
      );
      expect(match2, '192.168.100.231');
    });

    test('Numerical IPv4 Comparison', () {
      expect(
        NetworkUtils.compareIps('172.21.168.2', '172.21.168.10') < 0,
        isTrue,
      );
      expect(
        NetworkUtils.compareIps('172.21.170.16', '172.21.175.40') < 0,
        isTrue,
      );
      expect(NetworkUtils.compareIps('192.168.1.1', '192.168.1.1'), 0);
    });
  });
}
