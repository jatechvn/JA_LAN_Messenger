import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';

void main() {
  test(
    'JA HELLO marker preserves native timestamp domain and hostname fields',
    () {
      final raw = utf8.decode(
        ProtocolBeebeep.buildHelloPacket(
          localPort: 6475,
          username: 'Test',
          status: PeerStatus.online,
          statusDescription: '',
          accountName: 'test',
          appVersion: '1.4.0',
          avatarHexColor: '#123456',
          workgroup: '',
          hostname: 'PC',
        ),
      );
      final fields = (ProtocolBeebeep.parseMessage(raw)!['text'] as String)
          .split(ProtocolBeebeep.dataFieldSeparator);
      expect(fields[12], isEmpty);
      expect(fields[13], isEmpty);
      expect(fields[14], 'PC');
      expect(fields[15].trim(), 'JA_LAN_MESSENGER');
      expect(
        ProtocolBeebeep.parseHelloPacket(raw)!['client'],
        'JA_LAN_MESSENGER',
      );
    },
  );
}
