import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/peer_model.dart';

class ProtocolBeebeep {
  static const protocolFieldSeparator = '\u2029';
  static const dataFieldSeparator = '\u2028';
  static const headerBeep = 'BEE-BEEP',
      headerCiao = 'BEE-CIAO',
      headerChat = 'BEE-CHAT',
      headerGroup = 'BEE-GROU',
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
  static const idUserMessage = 16;
  static const flagUserVCard = 16;
  static const jaAvatarMarker = 'ja-avatar:';
  // Native Request=128, Refused=32 (sender leaves), Delete=512 (recipient removed).
  // JA disband uses Delete plus an explicit metadata marker.
  static const flagGroupUpdate = 128;
  static const flagGroupDisbanded = 512;
  static const flagGroupLeft = 32; // BeeBEEP Refused: remove sender.
  static const flagGroupKicked = 512; // BeeBEEP Delete: remove recipient.
  static const groupDisbandMarker = 'ja-group-v1:disband';
  static const groupInvitePrefix = 'ja-group-v1:invite:';
  static const groupAvatarPrefix = 'ja-group-v1:avatar:';
  static const groupCreatorPrefix = 'ja-group-v1:creator:';

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
      '', // Native BeeBEEP statusChangedIn (ISO timestamp).
      '',
      hostname,
      'JA_LAN_MESSENGER', // Optional JA extension after native HELLO fields.
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
      'hash': parts[7],
      'color': parts[8],
      'workgroup': parts[9],
      'datastreamVersion': int.tryParse(parts[11]) ?? 0,
      'protocolVersion': int.parse(message['id'] as String),
      'flags': message['flags'],
      'auth': message['data'],
      'client': parts.length > 15
          ? parts[15]
          : (parts.length > 12 && parts[12] == 'JA_LAN_MESSENGER'
                ? parts[12]
                : ''),
      'hostname': parts.length > 14 ? parts[14] : '',
    };
  }

  /// Xác định chính xác thiết bị đầu xa có thực sự là phần mềm BeeBEEP gốc hay không
  /// Tránh đánh dấu nhầm JA LAN Messenger là BeeBEEP
  static bool isRemoteBeebeep({
    required String version,
    required String color,
    String client = '',
  }) {
    // Nếu có chữ ký định danh JA_LAN_MESSENGER rõ ràng
    if (client == 'JA_LAN_MESSENGER' || client.contains('JA_')) return false;

    // Giao thức avatar của JA LAN Messenger chứa payload '|preset:' hoặc '|b64:'
    if (color.contains('|preset:') || color.contains('|b64:')) return false;

    // Phiên bản ứng dụng JA LAN Messenger là dòng 1.x.x hoặc chứa 'JA'
    if (version.startsWith('1.') || version.contains('JA')) return false;

    // Phần mềm BeeBEEP chính thức (C++/Qt) thuộc các dòng 5.x.x, 4.x.x, 3.x.x
    if (version.startsWith('5.') ||
        version.startsWith('4.') ||
        version.startsWith('3.')) {
      return true;
    }

    return false;
  }

  static List<int> buildChatPacket({
    required String messageId,
    required String text,
    String? recipientId,
    String? groupId,
    String? groupName,
    DateTime? groupUpdatedAt,
  }) => packet(
    headerChat,
    messageId,
    text: text,
    flags: groupId == null ? 1 : 256,
    data: [
      '',
      groupId ?? '',
      groupName ?? '',
      groupUpdatedAt?.toUtc().toIso8601String() ?? '',
    ].join(dataFieldSeparator),
  );

  // Native BeeBEEP group requests exclude the sender and recipient from records.
  static List<int> buildGroupPacket({
    required String groupId,
    required String name,
    required DateTime updatedAt,
    required List<List<String>> members,
    bool removed = false,
    bool left = false,
    bool kicked = false,
    DateTime? invitedAt,
    String? avatarPayload,
    String? creatorId,
    List<String>? adminIds,
  }) {
    final extensions = <String>[];
    if (removed) {
      extensions.add(groupDisbandMarker);
    } else if (!left && !kicked && invitedAt != null) {
      extensions.add(
        '$groupInvitePrefix${invitedAt.toUtc().toIso8601String()}',
      );
    }
    if (!removed &&
        !left &&
        !kicked &&
        avatarPayload != null &&
        avatarPayload.isNotEmpty) {
      // v1.3.0 accepts at most six data fields. Its avatar parser ignores
      // unknown pipe attributes, so carry ownership alongside the avatar.
      final owner = creatorId != null && creatorId.isNotEmpty
          ? '|creator:${Uri.encodeComponent(creatorId)}'
          : '';
      extensions.add(
        '$groupAvatarPrefix$avatarPayload$owner${_adminMarkup(adminIds)}',
      );
    }
    if (!removed &&
        (avatarPayload == null || avatarPayload.isEmpty || left || kicked) &&
        creatorId != null &&
        creatorId.isNotEmpty) {
      extensions.add(
        '$groupCreatorPrefix${Uri.encodeComponent(creatorId)}${_adminMarkup(adminIds)}',
      );
    }

    return packet(
      headerGroup,
      '${DateTime.now().microsecondsSinceEpoch}',
      flags: removed
          ? flagGroupDisbanded
          : kicked
          ? flagGroupKicked
          : left
          ? flagGroupLeft
          : flagGroupUpdate,
      data: [
        '',
        groupId,
        name,
        updatedAt.toUtc().toIso8601String(),
        ...extensions,
      ].join(dataFieldSeparator),
      text: members.isEmpty
          ? ''
          : [
              '${members.length}',
              ...members.expand((m) => m),
            ].join(protocolFieldSeparator),
    );
  }

  static ({
    String id,
    String name,
    DateTime updatedAt,
    bool hasRevision,
    bool disbanded,
    DateTime? invitedAt,
    String? avatarPayload,
    String? creatorId,
    List<String>? adminIds,
  })?
  groupMetadata(Map<String, dynamic> message) {
    final fields = (message['data'] as String? ?? '').split(dataFieldSeparator);
    if (fields.length < 4 ||
        fields.length > 8 ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$').hasMatch(fields[1]) ||
        fields[2].trim().isEmpty ||
        fields[2].length > 256) {
      return null;
    }
    final control = ((message['flags'] as int? ?? 0) & (32 | 512)) != 0;
    final date = fields[3].isEmpty && control
        ? message['timestamp'] as DateTime?
        : DateTime.tryParse(fields[3]);
    if (date == null) return null;

    var disbanded = false;
    DateTime? invitedAt;
    String? avatarPayload;
    String? creatorId;
    List<String>? adminIds;

    for (int i = 4; i < fields.length; i++) {
      final ext = fields[i];
      if (ext == groupDisbandMarker) {
        disbanded = true;
      } else if (ext.startsWith(groupInvitePrefix)) {
        invitedAt = DateTime.tryParse(ext.substring(groupInvitePrefix.length));
      } else if (ext.startsWith(groupAvatarPrefix)) {
        final parsed = _parseRoleMarkup(
          ext.substring(groupAvatarPrefix.length),
        );
        avatarPayload = parsed.payload;
        creatorId = parsed.creatorId ?? creatorId;
        adminIds = parsed.adminIds ?? adminIds;
      } else if (ext.startsWith(groupCreatorPrefix)) {
        final parsed = _parseRoleMarkup(
          ext.substring(groupCreatorPrefix.length),
        );
        creatorId = parsed.creatorId ?? parsed.payload;
        adminIds = parsed.adminIds ?? adminIds;
      }
    }

    if (invitedAt != null && invitedAt.isAfter(date)) return null;
    return (
      id: fields[1],
      name: fields[2],
      updatedAt: date,
      hasRevision: fields[3].isNotEmpty,
      disbanded: disbanded,
      invitedAt: invitedAt,
      avatarPayload: avatarPayload,
      creatorId: creatorId,
      adminIds: adminIds,
    );
  }

  static String _adminMarkup(List<String>? adminIds) {
    if (adminIds == null) return '';
    final ids = adminIds.where((id) => id.isNotEmpty).toSet().join(',');
    return '|admins:${Uri.encodeComponent(ids)}';
  }

  static ({String? payload, String? creatorId, List<String>? adminIds})
  _parseRoleMarkup(String raw) {
    final parts = raw.split('|');
    final kept = <String>[];
    String? creatorId;
    List<String>? adminIds;
    for (final part in parts) {
      if (part.startsWith('creator:')) {
        try {
          creatorId = Uri.decodeComponent(part.substring(8));
        } on FormatException {
          continue;
        }
      } else if (part.startsWith('admins:')) {
        try {
          adminIds = Uri.decodeComponent(
            part.substring(7),
          ).split(',').where((id) => id.isNotEmpty).toList();
        } on FormatException {
          continue;
        }
      } else {
        kept.add(part);
      }
    }
    final payload = kept.join('|');
    return (
      payload: payload.isEmpty ? null : payload,
      creatorId: creatorId,
      adminIds: adminIds,
    );
  }

  static List<List<String>>? groupRecords(String text) {
    if (text.isEmpty) return [];
    final fields = text.split(protocolFieldSeparator);
    final count = int.tryParse(fields.first);
    if (count == null ||
        count < 0 ||
        count > 512 ||
        fields.length != 1 + count * 4) {
      return null;
    }
    return [
      for (var i = 0; i < count; i++) fields.sublist(1 + i * 4, 5 + i * 4),
    ];
  }

  static List<int> buildReceivedAckPacket(String messageId) =>
      packet(headerRecv, '26', text: messageId, flags: 128);

  static List<int> buildTypingPacket({
    required bool isTyping,
    String? groupId,
  }) => packet(
    headerUser,
    '$idWritingMessage',
    data: groupId ?? '',
    text: isTyping ? '*' : '',
    flags: isTyping ? 3 : 1,
  );

  /// Native BeeBEEP vCard: id 16, UserVCard flag, at least five data fields,
  /// and plain PNG Base64 in text. JA preset metadata rides in the info field.
  static List<int> buildAvatarUpdatePacket({
    required String nickname,
    required String colorHex,
    String photoBase64 = '',
    String jaPayload = '',
  }) {
    final safeName = nickname
        .replaceAll(dataFieldSeparator, ' ')
        .replaceAll(protocolFieldSeparator, ' ');
    final color = colorHex.startsWith('#') ? colorHex : '#$colorHex';
    final fields = <String>[
      safeName,
      '',
      '',
      '',
      '',
      color,
      '',
      '',
      'N',
      if (jaPayload.isNotEmpty) '$jaAvatarMarker$jaPayload',
    ];
    return packet(
      headerUser,
      '$idUserMessage',
      data: fields.join(dataFieldSeparator),
      text: photoBase64,
      flags: flagUserVCard,
    );
  }

  /// Turns a native vCard or a legacy JA `avatar:` packet into `#color|...`.
  static String? normalizeAvatarPayload(Map<String, dynamic> message) {
    final data = message['data'] as String? ?? '';
    final text = (message['text'] as String? ?? '').trim();
    if (data.startsWith('avatar:')) {
      final payload = data.substring('avatar:'.length).trim();
      return payload.isEmpty ? null : payload;
    }
    final fields = data.split(dataFieldSeparator);
    if (fields.length < 5) return null;
    for (final field in fields) {
      if (field.startsWith(jaAvatarMarker)) {
        final payload = field.substring(jaAvatarMarker.length).trim();
        if (payload.isNotEmpty) return payload;
      }
    }
    final color = fields.length > 5 && fields[5].trim().startsWith('#')
        ? fields[5].trim()
        : '#000000';
    if (text.isNotEmpty && !text.startsWith('#')) {
      return '$color|b64:$text';
    }
    return color;
  }

  static List<int> buildReadPacket(String messageId) =>
      packet(headerRead, '27', text: messageId, flags: 128);

  static List<int> buildRevokePacket(String messageId) =>
      packet(headerRevoke, '35', text: messageId, flags: 1);

  static List<int> buildReactionPacket({
    required String messageId,
    required String emoji,
    required String action,
    required String senderName,
  }) => packet(
    headerReaction,
    '40',
    text: '$messageId$dataFieldSeparator$emoji$dataFieldSeparator$action',
    data: senderName,
    flags: 1,
  );

  static Map<String, String>? parseReactionPacket(
    Map<String, dynamic> message,
  ) {
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
    final timestamp = DateTime.tryParse(parts[5])?.toLocal();
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
