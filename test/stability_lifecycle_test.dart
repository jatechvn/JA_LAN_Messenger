import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:ja_lan_messenger/modules/bounded_log.dart';
import 'package:ja_lan_messenger/modules/network/file_transfer_engine.dart';
import 'package:ja_lan_messenger/modules/models/file_transfer_task.dart';
import 'package:ja_lan_messenger/modules/network/lan_tcp_server.dart';
import 'file_transfer_test.dart' show hello;

void main() {
  test(
    'diagnostic rotation stays bounded and discards arbitrary payloads',
    () async {
      final dir = await Directory.systemTemp.createTemp('ja_log_test');
      addTearDown(() => dir.delete(recursive: true));
      final log = BoundedLog(dir, 'test', maxBytes: 256, slots: 3);
      for (var i = 0; i < 100; i++) {
        log.write(LogRecord(Level.INFO, 'password=secret private chat', 'AI'));
      }
      final files = dir.listSync().whereType<File>().toList();
      expect(files.length, lessThanOrEqualTo(3));
      for (final file in files) {
        expect(await file.length(), lessThanOrEqualTo(256));
        expect(await file.readAsString(), isNot(contains('secret')));
      }
    },
  );
  test(
    'stop prevents pending TCP connection attaching to a restarted server',
    () async {
      final remote = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      remote.listen(sockets.add);
      final tcp = LanTcpServer()..helloBuilder = (key) => hello(key, 51001);
      addTearDown(() async {
        await tcp.stop();
        for (final socket in sockets) {
          socket.destroy();
        }
        await remote.close();
      });
      await tcp.start(port: 0);
      final pending = tcp.connect('127.0.0.1', remote.port);
      await tcp.stop();
      await tcp.start(port: 0);
      expect(await pending.timeout(const Duration(seconds: 3)), false);
    },
  );
  test('stalled download fails and exposes only a partial file', () async {
    final dir = await Directory.systemTemp.createTemp('ja_stall_test');
    final remote = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    remote.listen(sockets.add);
    final engine = FileTransferEngine(
      inactivityTimeout: const Duration(milliseconds: 100),
    );
    engine.downloadDirectory = dir.path;
    engine.helloBuilder = (key) => hello(key, 51001);
    engine.isPeerConnected = (_) => true;
    final failed = Completer<FileTransferTask>();
    engine.onTransferUpdated = (task) {
      if (task.status == TransferStatus.failed && !failed.isCompleted) {
        failed.complete(task);
      }
    };
    try {
      await engine.startServer(port: 0);
      await engine.receiveOffer('127.0.0.1:51002', '127.0.0.1', 'test', {
        'header': 'BEE-FILE',
        'text': 'image.png',
        'flags': 1,
        'data': '${remote.port}\u2028100\u2028123\u2028token',
      });
      final task = await failed.future.timeout(const Duration(seconds: 3));
      expect(task.filePath, endsWith('.part'));
      expect(
        await File(task.filePath.replaceFirst(RegExp(r'\.part$'), '')).exists(),
        false,
      );
    } finally {
      await engine.stop();
      for (final socket in sockets) {
        socket.destroy();
      }
      await remote.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await dir.delete(recursive: true);
    }
  });
}
