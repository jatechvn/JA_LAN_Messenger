import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'beebeep_session_test.dart' show hello;
import 'package:ja_lan_messenger/modules/network/lan_discovery.dart';

void main() {
  test(
    'live adapter discovery advances beyond zero',
    () async {
      final service = LanDiscoveryService();
      final tcp = LanTcpServer();
      tcp.helloBuilder = (key) => hello(key, tcp.port, 'JA scan diagnostic');
      await tcp.start(port: 56479);
      addTearDown(tcp.stop);
      service.connectCandidate = (ip, port, source) => tcp.connect(
        ip,
        port,
        sourceAddress: source,
        timeout: const Duration(milliseconds: 150),
      );
      final advanced = Completer<void>();
      addTearDown(service.stop);
      await service.start(
        localTcpPort: tcp.port,
        onScanState: (state) {
          if (state.activePhase == 'subnet_sweep' && state.progress >= 0.02) {
            if (!advanced.isCompleted) {
              debugPrint(
                'LIVE SCAN: ${state.statusText}; subnets=${state.activeSubnets}',
              );
              advanced.complete();
            }
          }
        },
      );
      await advanced.future.timeout(const Duration(seconds: 25));
    },
    skip: Platform.environment['JA_LIVE_SCAN'] != '1',
  );
}
