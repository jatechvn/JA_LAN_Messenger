import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import 'protocol_beebeep.dart';
import 'network_utils.dart';

class LanTcpClient {
  List<NetworkInterfaceDetails> _cachedAdapters = [];
  DateTime _lastAdapterCheck = DateTime.fromMillisecondsSinceEpoch(0);

  Future<String?> _resolveSourceAddress(String peerIp) async {
    try {
      final now = DateTime.now();
      if (_cachedAdapters.isEmpty ||
          now.difference(_lastAdapterCheck).inSeconds > 30) {
        _cachedAdapters = await NetworkUtils.getAvailableAdapters();
        _lastAdapterCheck = now;
      }
      return NetworkUtils.findMatchingLocalIp(peerIp, _cachedAdapters);
    } catch (_) {
      return null;
    }
  }

  /// Gửi gói tin bất kỳ tới peer qua TCP với sourceAddress tương ứng
  Future<bool> sendPacket({
    required String peerIp,
    int peerPort = defaultListenerPort,
    required List<int> packetBytes,
    Duration timeout = const Duration(seconds: 4),
    String? sourceAddress,
  }) async {
    Socket? socket;
    try {
      final source = sourceAddress ?? await _resolveSourceAddress(peerIp);

      socket = await Socket.connect(
        peerIp,
        peerPort,
        sourceAddress: source,
        timeout: timeout,
      );

      socket.add(packetBytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      debugPrint('[TcpClient] Error sending packet to $peerIp:$peerPort: $e');
      socket?.destroy();
      return false;
    }
  }

  /// Gửi lời chào Handshake (BEE-CIAO) tới máy bạn
  Future<bool> sendHandshake({
    required String peerIp,
    int peerPort = defaultListenerPort,
    required List<int> helloBytes,
    String? sourceAddress,
  }) async {
    return sendPacket(
      peerIp: peerIp,
      peerPort: peerPort,
      packetBytes: helloBytes,
      sourceAddress: sourceAddress,
    );
  }

  /// Gửi tin nhắn chat (BEE-CHAT)
  Future<bool> sendChatMessage({
    required String peerIp,
    int peerPort = defaultListenerPort,
    required String messageId,
    required String text,
    String? recipientId,
    String? sourceAddress,
  }) async {
    final packet = ProtocolBeebeep.buildChatPacket(
      messageId: messageId,
      text: text,
      recipientId: recipientId,
    );
    return sendPacket(
      peerIp: peerIp,
      peerPort: peerPort,
      packetBytes: packet,
      sourceAddress: sourceAddress,
    );
  }

  /// Gửi rung chuông Nudge/Buzz (BEE-BUZZ)
  Future<bool> sendBuzz({
    required String peerIp,
    int peerPort = defaultListenerPort,
    String? sourceAddress,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final fields = [
      ProtocolBeebeep.headerBuzz,
      '99',
      '0',
      '0',
      '',
      now,
      'Buzz',
    ];
    final raw = fields.join(ProtocolBeebeep.protocolFieldSeparator);
    return sendPacket(
      peerIp: peerIp,
      peerPort: peerPort,
      packetBytes: raw.codeUnits,
      sourceAddress: sourceAddress,
    );
  }
}
