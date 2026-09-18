import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';

void main() {
  group('ProtocolBeebeep Tests', () {
    test('Broadcast packet encoding and parsing', () {
      final packetBytes = ProtocolBeebeep.buildBroadcastPacket(
        localTcpPort: 6475,
        targetHostAddress: '255.255.255.255',
      );

      expect(packetBytes, isNotEmpty);
      final rawStr = utf8.decode(packetBytes);
      final parsedPort = ProtocolBeebeep.parseBroadcastPacket(rawStr);

      expect(parsedPort, equals(6475));
    });

    test('Hello / Handshake packet encoding and parsing', () {
      final helloBytes = ProtocolBeebeep.buildHelloPacket(
        localPort: 6475,
        username: 'TestUser',
        status: PeerStatus.online,
        statusDescription: 'Coding Flutter',
        accountName: 'test_account',
        appVersion: '1.0.0',
        avatarHexColor: '#3B82F6',
        workgroup: 'Engineering',
      );

      expect(helloBytes, isNotEmpty);
      final rawStr = utf8.decode(helloBytes);
      final parsed = ProtocolBeebeep.parseHelloPacket(rawStr);

      expect(parsed, isNotNull);
      expect(parsed!['username'], equals('TestUser'));
      expect(parsed['port'], equals(6475));
      expect(parsed['status'], equals(PeerStatus.online));
      expect(parsed['statusDescription'], equals('Coding Flutter'));
      expect(parsed['workgroup'], equals('Engineering'));
    });

    test('Chat message packet encoding and parsing', () {
      final chatBytes = ProtocolBeebeep.buildChatPacket(
        messageId: '12345',
        text: 'Hello from JA LAN Messenger!',
        recipientId: '192.168.1.50',
      );

      expect(chatBytes, isNotEmpty);
      final rawStr = utf8.decode(chatBytes);
      final parsed = ProtocolBeebeep.parseMessage(rawStr);

      expect(parsed, isNotNull);
      expect(parsed!['header'], equals(ProtocolBeebeep.headerChat));
      expect(parsed['id'], equals('12345'));
      expect(parsed['text'], equals('Hello from JA LAN Messenger!'));
    });
  });
}
