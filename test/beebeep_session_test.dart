import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/beebeep_key_exchange.dart';
import 'package:ja_lan_messenger/modules/network/beebeep_session.dart';
import 'package:ja_lan_messenger/modules/network/lan_discovery.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';

List<int> hello(String key, int port, String name) =>
    ProtocolBeebeep.buildHelloPacket(
      localPort: port,
      username: name,
      status: PeerStatus.online,
      statusDescription: '',
      accountName: name,
      appVersion: '1.0.0',
      avatarHexColor: '#112233',
      workgroup: '',
      publicKey: key,
    );

void main() {
  test('Qt UDP fixture and same-machine endpoint filtering', () {
    const fixture =
        'BEE-BEEP\u202911\u20294\u20290\u2029224.0.64.75\u20292026-09-16T10:00:00\u20296475      ';
    expect(ProtocolBeebeep.parseBroadcastPacket(fixture), 6475);
    expect(
      ProtocolBeebeep.parseBroadcastPacket(
        fixture.replaceFirst('6475      ', '0000      '),
      ),
      isNull,
    );
    expect(
      LanDiscoveryService.isOwnEndpoint('127.0.0.1', 6475, {'127.0.0.1'}, 6477),
      false,
    );
    expect(
      LanDiscoveryService.isOwnEndpoint('127.0.0.1', 6477, {'127.0.0.1'}, 6477),
      true,
    );
  });
  test('ECDH shared key is symmetric and rejects invalid points', () {
    final a = BeebeepKeyExchange(), b = BeebeepKeyExchange();
    expect(a.derive(b.publicKey), b.derive(a.publicKey));
    expect(
      () => a.derive(List.filled(48, '0').join(':')),
      throwsFormatException,
    );
  });
  test('AES-256 legacy HELLO matches known zero-key vector', () {
    final encrypted = BeebeepSession.crypt(
      Uint8List(16),
      Uint8List(32),
      encrypt: true,
    );
    expect(
      encrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'dc95c078a2408989ad48a21492842087',
    );
    expect(BeebeepSession.frame(encrypted, hello: true).take(6), [
      0,
      20,
      0,
      0,
      0,
      16,
    ]);
  });
  test(
    'persistent encrypted session handles fragmented HELLO and coalesced Unicode chats',
    () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = listener.first;
      final client = await Socket.connect('127.0.0.1', listener.port);
      final server = await accepted;
      final messages = <String>[];
      final received = Completer<void>();
      final session = BeebeepSession(
        server,
        helloBuilder: (key) => hello(key, listener.port, 'Server'),
        onHello: (_) {},
        onMessage: (m) {
          messages.add(m['text'] as String);
          if (messages.length == 2) received.complete();
        },
        onClosed: () {},
      );
      session.start(outgoing: false);
      final keys = BeebeepKeyExchange();
      final response = Completer<List<int>>();
      final bytes = <int>[];
      client.listen((chunk) {
        bytes.addAll(chunk);
        if (bytes.length >= 6) {
          final n = (bytes[0] << 8) | bytes[1];
          if (bytes.length >= n + 2 && !response.isCompleted) {
            response.complete(bytes.sublist(6, n + 2));
          }
        }
      });
      try {
        final initial = BeebeepSession.frame(
          BeebeepSession.crypt(
            hello(keys.publicKey, 54321, 'Client'),
            Uint8List(32),
            encrypt: true,
          ),
          hello: true,
        );
        client.add(initial.sublist(0, 3));
        await client.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        client.add(initial.sublist(3));
        final remote = ProtocolBeebeep.parseHelloPacket(
          utf8.decode(
            BeebeepSession.crypt(
              await response.future.timeout(const Duration(seconds: 10)),
              Uint8List(32),
              encrypt: false,
            ),
          ),
        )!;
        final key = keys.derive(remote['publicKey'] as String);
        client.add([
          for (final (id, text) in [
            ('1001', 'Xin chào 👋'),
            ('1002', '  tiếng Việt  '),
          ])
            ...BeebeepSession.frame(
              BeebeepSession.crypt(
                ProtocolBeebeep.buildChatPacket(messageId: id, text: text),
                key,
                encrypt: true,
              ),
              hello: false,
            ),
        ]);
        await received.future.timeout(const Duration(seconds: 10));
        expect(messages, ['Xin chào 👋', '  tiếng Việt  ']);
      } finally {
        session.close();
        client.destroy();
        await listener.close();
      }
    },
  );

  test(
    'installed BeeBEEP: authenticated HELLO and encrypted PONG on loopback',
    () async {
      final socket = await Socket.connect('127.0.0.1', 6475);
      final pong = Completer<void>();
      final ack = Completer<void>();
      final messageId = DateTime.now().microsecondsSinceEpoch.toString();
      late BeebeepSession session;
      session = BeebeepSession(
        socket,
        helloBuilder: (key) => hello(key, 56479, 'JA compatibility test'),
        onHello: (data) {
          expect(data['username'], isNotEmpty);
        },
        onMessage: (m) {
          if (m['header'] == ProtocolBeebeep.headerRecv &&
              m['text'] == messageId &&
              !ack.isCompleted) {
            ack.complete();
          }
          if (m['header'] == ProtocolBeebeep.headerPong && !pong.isCompleted) {
            pong.complete();
          }
        },
        onClosed: () {},
      );
      try {
        session.start(outgoing: true);
        expect(
          await session.ready.future.timeout(const Duration(seconds: 15)),
          true,
          reason: session.error,
        );
        session.send(
          ProtocolBeebeep.packet(ProtocolBeebeep.headerPing, '13', text: '*'),
        );
        await pong.future.timeout(const Duration(seconds: 15));
        if (Platform.environment['BEEBEEP_LOCAL_CHAT'] == '1') {
          session.send(
            ProtocolBeebeep.buildChatPacket(
              messageId: messageId,
              text:
                  'Kiểm tra tương thích JA ↔ BeeBEEP trên cùng máy. Tiếng Việt 👋',
            ),
          );
          await ack.future.timeout(const Duration(seconds: 15));
        }
      } finally {
        session.close();
      }
    },
    skip: Platform.environment['BEEBEEP_LOCAL_SMOKE'] != '1',
  );
}
