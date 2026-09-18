import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';

void main() {
  test(
    'failed connection completes and same endpoint can be retried',
    () async {
      final server = LanTcpServer();
      server.helloBuilder = (_) => [];
      await server.start(port: 0);
      addTearDown(server.stop);
      final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = unused.port;
      await unused.close();
      for (var i = 0; i < 2; i++) {
        expect(
          await server
              .connect('127.0.0.1', port)
              .timeout(const Duration(seconds: 3)),
          false,
        );
      }
    },
  );
}
