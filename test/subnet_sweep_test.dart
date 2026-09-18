import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/network/network_utils.dart';
import 'package:ja_lan_messenger/modules/network/subnet_sweep.dart';

NetworkInterfaceDetails adapter(String ip, String cidr) =>
    NetworkInterfaceDetails(
      name: 'test',
      ip: ip,
      subnet: cidr,
      isVirtual: false,
      isPrivateLan: true,
    );
void main() {
  test(
    'never completing probes time out and scan reaches completion',
    () async {
      final result = await SubnetSweep()
          .run(
            adapters: [adapter('10.0.0.1', '10.0.0.0/30')],
            localIps: {},
            interval: Duration.zero,
            probeTimeout: const Duration(milliseconds: 10),
            send: (_, _) => Completer<bool>().future,
          )
          .timeout(const Duration(seconds: 2));
      expect(result.attempted, 2);
      expect(result.sent, 0);
    },
  );
  test(
    'cancel releases workers waiting on stuck connections immediately',
    () async {
      final sweep = SubnetSweep();
      final started = Completer<void>();
      final run = sweep.run(
        adapters: [adapter('10.0.0.1', '10.0.0.0/30')],
        localIps: {},
        interval: Duration.zero,
        send: (_, _) {
          if (!started.isCompleted) started.complete();
          return Completer<bool>().future;
        },
      );
      await started.future;
      sweep.cancel();
      expect((await run.timeout(const Duration(seconds: 1))).cancelled, true);
    },
  );
  test('slow probe does not hold up progress of other workers', () async {
    final slow = Completer<bool>();
    final progress = Completer<void>();
    final run = SubnetSweep().run(
      adapters: [adapter('10.0.0.1', '10.0.0.0/29')],
      localIps: {},
      batchSize: 2,
      interval: Duration.zero,
      send: (_, ip) => ip == '10.0.0.1' ? slow.future : Future.value(true),
      onProgress: (done, _, sent) {
        if (done == 5) progress.complete();
      },
    );
    await progress.future.timeout(const Duration(seconds: 2));
    slow.complete(true);
    expect((await run).attempted, 6);
  });
  test(
    'async TCP probes are bounded and complete before scan finishes',
    () async {
      var running = 0, peak = 0, completed = 0;
      final result = await SubnetSweep().run(
        adapters: [adapter('172.21.174.100', '172.21.174.96/28')],
        localIps: {'172.21.174.100'},
        batchSize: 4,
        interval: Duration.zero,
        send: (nic, ip) async {
          running++;
          if (running > peak) peak = running;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          running--;
          completed++;
          return ip == '172.21.174.103';
        },
      );
      expect(peak, lessThanOrEqualTo(4));
      expect(completed, 13);
      expect(running, 0);
      expect(result.sent, 1);
    },
  );
  test('/21 covers every host including internal .0 and .255', () async {
    final targets = <String>{};
    final result = await SubnetSweep().run(
      adapters: [adapter('172.21.175.40', '172.21.168.0/21')],
      localIps: {'172.21.175.40'},
      interval: Duration.zero,
      send: (a, ip) {
        expect(a.ip, '172.21.175.40');
        expect(targets.add(ip), true);
        return true;
      },
    );
    expect(result.attempted, 2046);
    expect(result.sent, 2045);
    expect(targets.first, '172.21.168.1');
    expect(targets.last, '172.21.175.254');
    expect(
      targets,
      containsAll([
        '172.21.169.0',
        '172.21.168.255',
        '172.21.174.255',
        '172.21.175.0',
      ]),
    );
    expect(targets, isNot(contains('172.21.168.0')));
    expect(targets, isNot(contains('172.21.175.255')));
  });
  test('wide ranges are lazy; small CIDRs preserve host boundaries', () {
    expect(NetworkUtils.subnetHosts('10.2.3.4/8').take(2), [
      '10.0.0.1',
      '10.0.0.2',
    ]);
    expect(NetworkUtils.subnetHostCount('172.21.10.1/16'), 65534);
    expect(NetworkUtils.subnetHostCount('192.168.1.129/25'), 126);
    expect(NetworkUtils.getBroadcastIp('192.168.1.10/25'), '192.168.1.127');
    expect(NetworkUtils.subnetHosts('192.168.1.8/30'), [
      '192.168.1.9',
      '192.168.1.10',
    ]);
    expect(NetworkUtils.subnetHosts('192.168.1.8/31'), [
      '192.168.1.8',
      '192.168.1.9',
    ]);
    expect(NetworkUtils.subnetHosts('192.168.1.8/32'), ['192.168.1.8']);
    expect(
      () => NetworkUtils.subnetHostCount('192.168.1.8/33'),
      throwsFormatException,
    );
    expect(
      () => NetworkUtils.maskToPrefixLength('255.0.255.0'),
      throwsFormatException,
    );
  });
  test(
    'ipconfig mask parsing never pairs an IPv4 embedded in IPv6 or gateway',
    () {
      final masks = NetworkUtils.parseWindowsSubnetMasks('''Adapter one:
  DNS : 10.0.0.5
  IPv6 : fe80::ffff:192.168.100.1
  IPv4 : 172.21.175.40(Preferred)
  Mask : 255.255.248.0
  Gateway : 172.21.168.1

Adapter two:
  IPv4 : 192.168.100.231
  Mask : 255.255.255.0
''');
      expect(masks, {
        '172.21.175.40': '255.255.248.0',
        '192.168.100.231': '255.255.255.0',
      });
    },
  );
  test('cancellation stops a wide sweep and failures are counted', () async {
    final sweep = SubnetSweep();
    var sends = 0;
    final result = await sweep.run(
      adapters: [adapter('10.0.0.2', '10.0.0.0/8')],
      localIps: {},
      batchSize: 4,
      interval: Duration.zero,
      send: (_, ip) {
        sends++;
        if (sends == 5) sweep.cancel();
        return false;
      },
    );
    expect(result.cancelled, true);
    expect(sends, 5);
    expect(result.sent, 0);
    expect(result.attempted, 5);
  });
  test(
    'each adapter scans its own full CIDR through its source address',
    () async {
      final calls = <String>[];
      await SubnetSweep().run(
        adapters: [
          adapter('10.0.0.1', '10.0.0.0/30'),
          adapter('192.168.2.1', '192.168.2.0/30'),
        ],
        localIps: {'10.0.0.1', '192.168.2.1'},
        send: (a, ip) {
          calls.add('${a.ip}->$ip');
          return true;
        },
      );
      expect(calls, ['10.0.0.1->10.0.0.2', '192.168.2.1->192.168.2.2']);
    },
  );
}
