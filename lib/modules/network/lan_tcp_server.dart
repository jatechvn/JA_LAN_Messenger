import 'dart:async';
import 'package:logging/logging.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import 'beebeep_session.dart';
import 'protocol_beebeep.dart';

typedef OnHandshakeCallback =
    void Function(
      String senderIp,
      Map<String, dynamic> handshakeData,
      Socket socket,
    );
typedef OnMessageCallback =
    void Function(
      String senderId,
      String messageId,
      String text,
      DateTime timestamp,
    );
typedef OnAckCallback = void Function(String senderId, String messageId);
typedef OnBuzzCallback = void Function(String senderId);
typedef OnTypingCallback =
    void Function(String senderId, bool isTyping, [String? groupId]);
typedef OnReadCallback = void Function(String senderId, String messageId);
typedef OnRevokeCallback = void Function(String senderId, String messageId);
typedef OnReactionCallback =
    void Function(
      String endpoint,
      String messageId,
      String emoji,
      String action,
      String senderName,
    );

class LanTcpServer {
  ServerSocket? _serverSocket;
  int _generation = 0;
  int _port = defaultListenerPort;
  final Map<String, BeebeepSession> _sessions = {};
  final Set<BeebeepSession> _allSessions = {};
  final Map<String, Future<bool>> _connecting = {};
  List<int> Function(String publicKey)? helloBuilder;
  String Function()? passwordProvider;
  void Function(String endpoint, Map<String, dynamic> message)? onUserStatus;
  void Function(String endpoint, String avatarPayload)? onAvatarUpdate;
  OnHandshakeCallback? onHandshake;
  OnMessageCallback? onMessage;
  void Function(String endpoint, Map<String, dynamic> message)? onGroup;
  void Function(String endpoint, Map<String, dynamic> message)? onGroupMessage;
  OnAckCallback? onAck;
  void Function(String endpoint, Map<String, dynamic> message)? onFile;
  OnBuzzCallback? onBuzz;
  OnTypingCallback? onTyping;
  OnReadCallback? onRead;
  OnRevokeCallback? onRevoke;
  OnReactionCallback? onReaction;
  void Function(String endpoint)? onDisconnected;
  void Function(String endpoint)? onActivity;
  int get port => _port;
  bool get isListening => _serverSocket != null;

  Future<bool> start({int port = defaultListenerPort}) async {
    if (isListening) return true;
    for (final candidate in [port, port + 2, port + 4, 0]) {
      try {
        _serverSocket = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          candidate,
        );
        _port = _serverSocket!.port;
        _serverSocket!.listen((socket) => _attach(socket, outgoing: false));
        debugPrint('[TcpServer] Listening on $_port');
        return true;
      } catch (e) {
        debugPrint('[TcpServer] Cannot bind $candidate: $e');
      }
    }
    return false;
  }

  BeebeepSession _attach(Socket socket, {required bool outgoing}) {
    final remoteIp = socket.remoteAddress.address;
    final generation = _generation;
    String? endpoint;
    late BeebeepSession session;
    session = BeebeepSession(
      socket,
      password: passwordProvider?.call() ?? '',
      helloBuilder: (key) => helloBuilder!(key),
      onHello: (hello) {
        if (generation != _generation || !isListening) {
          session.close('Stale connection');
          return;
        }
        endpoint = '$remoteIp:${hello['port']}';
        final previous = _sessions[endpoint];
        // Both peers may connect simultaneously. Choose the same physical
        // connection at both ends using the advertised endpoint ordering.
        if (previous != null && previous.isReady) {
          final local = '${socket.address.address}:$_port';
          final preferOutgoing = local.compareTo(endpoint!) < 0;
          if (outgoing != preferOutgoing) {
            session.close();
            return;
          }
        }
        _sessions[endpoint!] = session;
        previous?.close();
        onHandshake?.call(remoteIp, hello, socket);
      },
      onMessage: (message) {
        if (endpoint == null) return;
        onActivity?.call(endpoint!);
        final header = message['header'] as String,
            text = message['text'] as String;
        switch (header) {
          case ProtocolBeebeep.headerChat:
            if ((message['flags'] as int) & (1 << 8) != 0) {
              onGroupMessage?.call(endpoint!, message);
              session.send(
                ProtocolBeebeep.buildReceivedAckPacket(message['id'] as String),
              );
              return;
            }
            onMessage?.call(
              endpoint!,
              message['id'] as String,
              text,
              message['timestamp'] as DateTime,
            );
            session.send(
              ProtocolBeebeep.buildReceivedAckPacket(message['id'] as String),
            );
          case ProtocolBeebeep.headerFile:
            onFile?.call(endpoint!, message);
          case ProtocolBeebeep.headerGroup:
            onGroup?.call(endpoint!, message);
          case ProtocolBeebeep.headerRecv:
            onAck?.call(endpoint!, text);
          case ProtocolBeebeep.headerRead:
            onRead?.call(endpoint!, text);
          case ProtocolBeebeep.headerRevoke:
            onRevoke?.call(endpoint!, text);
          case ProtocolBeebeep.headerReaction:
            final parsed = ProtocolBeebeep.parseReactionPacket(message);
            if (parsed != null) {
              onReaction?.call(
                endpoint!,
                parsed['messageId']!,
                parsed['emoji']!,
                parsed['action']!,
                parsed['senderName']!,
              );
            }
          case ProtocolBeebeep.headerUser:
            final flags = (message['flags'] as int?) ?? 0;
            if (flags & 2 != 0) {
              // Message::UserWriting flag
              final gId = (message['data'] as String? ?? '').trim();
              onTyping?.call(endpoint!, text == '*', gId.isEmpty ? null : gId);
            } else if (flags & 4 != 0) {
              onUserStatus?.call(endpoint!, message);
            } else if (flags & ProtocolBeebeep.flagUserVCard != 0 ||
                message['id'] == '15' ||
                (message['data'] as String? ?? '').startsWith('avatar:')) {
              final payload = ProtocolBeebeep.normalizeAvatarPayload(message);
              if (payload != null && payload.isNotEmpty) {
                onAvatarUpdate?.call(endpoint!, payload);
              }
            }
          case ProtocolBeebeep.headerBuzz:
            onBuzz?.call(endpoint!);
        }
      },
      onClosed: () {
        Logger(
          'Diagnostics',
        ).info('peer_disconnected error=${session.error != null}');
        _allSessions.remove(session);
        if (endpoint != null && identical(_sessions[endpoint], session)) {
          _sessions.remove(endpoint);
          onDisconnected?.call(endpoint!);
        }
        if (session.error != null) {
          debugPrint('[BeeBEEP] $remoteIp: ${session.error}');
        }
      },
    );
    _allSessions.add(session);
    session.start(outgoing: outgoing);
    return session;
  }

  Future<bool> connect(
    String ip,
    int port, {
    String? sourceAddress,
    Duration timeout = const Duration(seconds: 2),
  }) {
    final endpoint = '$ip:$port';
    if (_sessions[endpoint]?.isReady ?? false) return Future.value(true);
    final existing = _connecting[endpoint];
    if (existing != null) return existing;
    late Future<bool> pending;
    pending = _connect(ip, port, sourceAddress: sourceAddress, timeout: timeout)
        .whenComplete(() {
          if (identical(_connecting[endpoint], pending)) {
            _connecting.remove(endpoint);
          }
        });
    _connecting[endpoint] = pending;
    return pending;
  }

  Future<bool> _connect(
    String ip,
    int port, {
    String? sourceAddress,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!isListening || helloBuilder == null) return false;
    final generation = _generation;
    try {
      final socket = await Socket.connect(
        ip,
        port,
        sourceAddress: sourceAddress,
        timeout: timeout,
      );
      if (!isListening || generation != _generation) {
        socket.destroy();
        return false;
      }
      final session = _attach(socket, outgoing: true);
      return await session.ready.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          session.close('HELLO timeout');
          return false;
        },
      );
    } catch (e) {
      debugPrint('[BeeBEEP] Connect $ip:$port: $e');
      return false;
    }
  }

  bool send(String endpoint, List<int> packet) =>
      _sessions[endpoint]?.send(packet) ?? false;
  void sendToAll(List<int> packet) {
    for (final session in _allSessions) {
      if (session.isReady) {
        session.send(packet);
      }
    }
  }

  bool isConnected(String endpoint) => _sessions[endpoint]?.isReady ?? false;
  void invalidatePendingConnections() {
    _generation++;
    _connecting.clear();
  }

  void closeConnections() {
    invalidatePendingConnections();
    for (final session in _allSessions.toList()) {
      session.close();
    }
  }

  Future<void> stop() async {
    final server = _serverSocket;
    _serverSocket = null;
    _generation++;
    _connecting.clear();
    for (final session in _allSessions.toList()) {
      session.close();
    }
    await server?.close();
  }
}
