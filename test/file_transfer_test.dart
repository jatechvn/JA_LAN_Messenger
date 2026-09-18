import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/network/file_transfer_engine.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/models/file_transfer_task.dart';

List<int> hello(String key, int port) => ProtocolBeebeep.buildHelloPacket(
  localPort: port,
  username: 'Test $port',
  status: PeerStatus.online,
  statusDescription: '',
  accountName: 'test',
  appVersion: '1.0',
  avatarHexColor: '#112233',
  workgroup: '',
  publicKey: key,
);
void main() {
  test(
    'disconnected receiver fails instead of reporting a successful upload',
    () async {
      final temp = await Directory.systemTemp.createTemp('ja-offer-test-');
      final engine = FileTransferEngine();
      try {
        final file = await File(
          '${temp.path}/test.bin',
        ).writeAsBytes([1, 2, 3]);
        final task = await engine.sendFile(
          peerId: '127.0.0.1:1234',
          peerIp: '127.0.0.1',
          peerName: 'offline',
          file: file,
        );
        expect(task.status, TransferStatus.failed);
        expect(task.transferredBytes, 0);
      } finally {
        await engine.stop();
        await temp.delete(recursive: true);
      }
    },
  );
  test('invalid file metadata is rejected', () {
    for (final data in [
      '0\u20281\u2028123\u2028secret',
      '6476\u2028-1\u2028123\u2028secret',
      '6476\u20281\u20280\u2028secret',
    ]) {
      expect(
        () => FileTransferEngine.parseOffer({
          'header': 'BEE-FILE',
          'text': 'test',
          'data': data,
        }),
        throwsFormatException,
      );
    }
  });

  for (final size in [0, 15, 16, 65539, 150001]) {
    test('confirmed encrypted transfer $size bytes', () async {
      final temp = await Directory.systemTemp.createTemp('ja-file-test-');
      final a = FileTransferEngine(), b = FileTransferEngine();
      final received = Completer<FileTransferTask>(),
          sent = Completer<FileTransferTask>();
      a.helloBuilder = (key) => hello(key, 51001);
      b.helloBuilder = (key) => hello(key, 51002);
      a.isPeerConnected = (id) => id == '127.0.0.1:51002';
      b.isPeerConnected = (id) => id == '127.0.0.1:51001';
      b.downloadDirectory = '${temp.path}/downloads';
      a.onTransferUpdated = (t) {
        if ([
              TransferStatus.completed,
              TransferStatus.failed,
            ].contains(t.status) &&
            !sent.isCompleted) {
          sent.complete(t);
        }
      };
      b.onTransferUpdated = (t) {
        if ([
              TransferStatus.completed,
              TransferStatus.failed,
            ].contains(t.status) &&
            !received.isCompleted) {
          received.complete(t);
        }
      };
      a.sendOffer = (_, bytes) {
        unawaited(
          b.receiveOffer(
            '127.0.0.1:51001',
            '127.0.0.1',
            'Sender',
            ProtocolBeebeep.parseMessage(utf8.decode(bytes))!,
          ),
        );
        return true;
      };
      try {
        await a.startServer(port: 0);
        await b.startServer(port: 0);
        final data = List.generate(size, (i) => i * 71 % 256);
        final file = await File(
          '${temp.path}/ảnh tiếng Việt.png',
        ).writeAsBytes(data);
        final task = await a.sendFile(
          peerId: '127.0.0.1:51002',
          peerIp: '127.0.0.1',
          peerName: 'Receiver',
          file: file,
        );
        expect(task.status, TransferStatus.pending);
        final download = await received.future.timeout(
          const Duration(seconds: 15),
        );
        final upload = await sent.future.timeout(const Duration(seconds: 15));
        expect(
          download.status,
          TransferStatus.completed,
          reason: download.errorMessage,
        );
        expect(
          upload.status,
          TransferStatus.completed,
          reason: upload.errorMessage,
        );
        expect(download.peerId, '127.0.0.1:51001');
        expect(await File(download.filePath).readAsBytes(), data);
        expect(upload.transferredBytes, size);
      } finally {
        await a.stop();
        await b.stop();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await temp.delete(recursive: true);
      }
    });
  }
}
