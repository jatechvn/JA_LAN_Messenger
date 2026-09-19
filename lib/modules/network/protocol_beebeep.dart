import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/peer_model.dart';

class ProtocolBeebeep {
  static const protocolFieldSeparator = '\u2029';
  static const dataFieldSeparator = '\u2028';
  static const headerBeep = 'BEE-BEEP',
      headerCiao = 'BEE-CIAO',
      headerChat = 'BEE-CHAT',
      headerRecv = 'BEE-RECV',
      headerRead = 'BEE-READ',
      headerUser = 'BEE-USER',
      headerFile = 'BEE-FILE',
      headerBuzz = 'BEE-BUZZ',
      headerPing = 'BEE-PING',
      headerPong = 'BEE-PONG',
      headerRevoke = 'BEE-RCOV',
      headerReaction = 'BEE-REACT';
  static const protocolVersion = 95;
  static const idWritingMessage = 12;

  static String authenticationHash(String username, {String password = ''}) {
    final passwordHash = sha1
        .convert(utf8.encode(password.isEmpty ? '*6475*' : password))
        .toString();
    return sha1.convert(utf8.encode(username + passwordHash)).toString();
  }

  static List<int> packet(
    String header,
    String id, {
    String text = '',
    String data = '',
    int flags = 0,
  }) {
    final timestamp =
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final bytes = utf8.encode(
      [
        header,
        id,
        text.length.toString(),
        '$flags',
        data,
        timestamp,
        text,
      ].join(protocolFieldSeparator),
    );
    return [...bytes, ...List.filled((16 - bytes.length % 16) % 16, 32)];
  }

  static List<int> buildBroadcastPacket({
    required int localTcpPort,
    required String targetHostAddress,
  }) =>
      packet(headerBeep, '11', text: '$localTcpPort', data: targetHostAddress);

  static int? parseBroadcastPacket(String payload) {
    final message = parseMessage(payload);
    if (message == null || message['header'] != headerBeep) return null;
    final port = int.tryParse(message['text'] as String);
    return port != null && port > 0 && port <= 65535 ? port : null;
  }

  static List<int> buildHelloPacket({
    required int localPort,
    required String username,
    required PeerStatus status,
    required String statusDescription,
    required String accountName,
    required String appVersion,
    required String avatarHexColor,
    required String workgroup,
    String publicKey = '',
    String password = '',
    String hostname = '',
  }) {
    final text = [
      '$localPort',
      username,
      '${_statusToInt(status)}',
      statusDescription,
      accountName,
      publicKey,
      appVersion,
      sha256
          .convert(utf8.encode('$accountName@$hostname:$localPort'))
          .toString(),
      avatarHexColor,
      workgroup,
      '5.15.2',
      '19',
      '',
      '',
      hostname,
    ].join(dataFieldSeparator);
    return packet(
      headerCiao,
      '$protocolVersion',
      text: text,
      data: authenticationHash(username, password: password),
    );
  }

  static Map<String, dynamic>? parseHelloPacket(String payload) {
    final message = parseMessage(payload);
    if (message == null || message['header'] != headerCiao) return null;
    final parts = (message['text'] as String).split(dataFieldSeparator);
    if (parts.length < 12) return null;
    final port = int.tryParse(parts[0]);
    if (port == null || port < 1 || port > 65535) return null;
    return {
      'port': port,
      'username': parts[1],
      'status': _intToStatus(int.tryParse(parts[2]) ?? 1),
      'statusDescription': parts[3],
      'account': parts[4],
      'publicKey': parts[5],
      'version': parts[6],
      'color': parts[8],
      'workgroup': parts[9],
      'datastreamVersion': int.tryParse(parts[11]) ?? 0,
      'protocolVersion': int.parse(message['id'] as String),
      'flags': message['flags'],
      'auth': message['data'],
      'hostname': parts.length > 14 ? parts[14] : '',
    };
  }

  static List<int> buildChatPacket({
    required String messageId,
    required String text,
    String? recipientId,
  }) => packet(
    headerChat,
    messageId,
    text: text,
    flags: 1,
    data: List.filled(4, '').join(dataFieldSeparator),
  );
  static List<int> buildReceivedAckPacket(String messageId) =>
      packet(headerRecv, '26', text: messageId, flags: 128);

  static List<int> buildTypingPacket({required bool isTyping}) => packet(
    headerUser,
    '$idWritingMessage',
    text: isTyping ? '*' : '',
    flags: isTyping ? 3 : 1,
  );

  static List<int> buildReadPacket(String messageId) =>
      packet(headerRead, '27', text: messageId, flags: 128);

  static List<int> buildRevokePacket(String messageId) =>
      packet(headerRevoke, '35', text: messageId, flags: 1);

  static List<int> buildReactionPacket({
    required String messageId,
    required String emoji,
    required String action,
    required String senderName,
  }) =>
      packet(
        headerReaction,
        '40',
        text: '$messageId$dataFieldSeparator$emoji$dataFieldSeparator$action',
        data: senderName,
        flags: 1,
      );

  static Map<String, String>? parseReactionPacket(Map<String, dynamic> message) {
    if (message['header'] != headerReaction) return null;
    final text = message['text'] as String? ?? '';
    final parts = text.split(dataFieldSeparator);
    if (parts.length < 3) return null;
    return {
      'messageId': parts[0],
      'emoji': parts[1],
      'action': parts[2],
      'senderName': message['data'] as String? ?? '',
    };
  }

  static Map<String, dynamic>? parseMessage(String payload) {
    final parts = payload.split(protocolFieldSeparator);
    if (parts.length < 7 || !(parts[0].startsWith('BEE-'))) return null;
    final id = int.tryParse(parts[1]),
        length = int.tryParse(parts[2]),
        flags = int.tryParse(parts[3]);
    final timestamp = DateTime.tryParse(parts[5]);
    final text = parts.sublist(6).join(protocolFieldSeparator);
    if (id == null ||
        id <= 0 ||
        length == null ||
        length < 0 ||
        length > text.length ||
        flags == null ||
        timestamp == null) {
      return null;
    }
    return {
      'header': parts[0],
      'id': parts[1],
      'textLen': length,
      'flags': flags,
      'data': parts[4],
      'timestamp': timestamp,
      'text': text.substring(0, length),
    };
  }

  static int _statusToInt(PeerStatus status) => switch (status) {
    PeerStatus.online => 1,
    PeerStatus.busy => 2,
    PeerStatus.away => 3,
    PeerStatus.offline => 0,
  };
  static PeerStatus _intToStatus(int status) => switch (status) {
    1 => PeerStatus.online,
    2 => PeerStatus.busy,
    3 => PeerStatus.away,
    _ => PeerStatus.offline,
  };
}
