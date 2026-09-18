import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'beebeep_key_exchange.dart';
import 'protocol_beebeep.dart';

/// One persistent, bidirectional BeeBEEP connection. HELLO always uses the
/// protocol-1 16-bit Qt frame and legacy AES key; subsequent frames use 32 bits
/// and the negotiated ECDH key. See ConnectionSocket.cpp in reference_sources.
class BeebeepSession {
  final Socket socket;
  final List<int> Function(String publicKey) helloBuilder;
  final void Function(Map<String, dynamic>) onHello;
  final void Function(Map<String, dynamic>) onMessage;
  final void Function() onClosed;
  final String password;
  final void Function(List<int>)? onData;
  final _keys = BeebeepKeyExchange();
  final _buffer = <int>[];
  final ready = Completer<bool>();
  Uint8List _key = Uint8List(32);
  bool _helloSent = false, _authenticated = false, _closed = false;
  Timer? _timer;
  DateTime _lastRead = DateTime.now();
  String? error;
  int? peerPort;
  bool get isReady => _authenticated && !_closed;

  BeebeepSession(
    this.socket, {
    required this.helloBuilder,
    required this.onHello,
    required this.onMessage,
    required this.onClosed,
    this.password = '',
    this.onData,
  });

  void start({required bool outgoing}) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.listen(
      _read,
      onError: (Object e) => close(e.toString()),
      onDone: close,
    );
    if (outgoing) _sendHello();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (DateTime.now().difference(_lastRead).inSeconds > 28) {
        close('BeeBEEP connection timeout');
      } else if (isReady && onData == null) {
        send(
          ProtocolBeebeep.packet(ProtocolBeebeep.headerPing, '13', text: '*'),
        );
      }
    });
  }

  static Uint8List crypt(
    List<int> input,
    Uint8List key, {
    required bool encrypt,
  }) {
    // BeeBEEP encrypts complete AES blocks and copies the trailing bytes verbatim.
    final aligned = input.length - input.length % 16;
    if (aligned == 0) return Uint8List.fromList(input);
    if (aligned != input.length) {
      return Uint8List.fromList([
        ...crypt(input.sublist(0, aligned), key, encrypt: encrypt),
        ...input.sublist(aligned),
      ]);
    }
    final cipher = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.ecb, padding: null),
    );
    return encrypt
        ? cipher.encryptBytes(input).bytes
        : Uint8List.fromList(
            cipher.decryptBytes(enc.Encrypted(Uint8List.fromList(input))),
          );
  }

  static Uint8List frame(List<int> bytes, {required bool hello}) {
    final prefix = hello ? 2 : 4;
    if (bytes.length > (hello ? 65519 : 4 * 1024 * 1024)) {
      throw const FormatException('BeeBEEP frame too large');
    }
    final result = Uint8List(prefix + 4 + bytes.length);
    final view = ByteData.sublistView(result);
    if (hello) {
      view.setUint16(0, bytes.length + 4);
    } else {
      view.setUint32(0, bytes.length + 4);
    }
    view.setUint32(prefix, bytes.length);
    result.setRange(prefix + 4, result.length, bytes);
    return result;
  }

  void _sendHello() {
    if (_helloSent) return;
    socket.add(
      frame(
        crypt(helloBuilder(_keys.publicKey), _key, encrypt: true),
        hello: true,
      ),
    );
    _helloSent = true;
  }

  bool send(List<int> payload) {
    if (!isReady) return false;
    try {
      socket.add(frame(crypt(payload, _key, encrypt: true), hello: false));
      return true;
    } catch (e) {
      close(e.toString());
      return false;
    }
  }

  void _read(List<int> bytes) {
    if (_closed) return;
    _buffer.addAll(bytes);
    try {
      while (!_closed) {
        final prefix = _authenticated ? 4 : 2;
        if (_buffer.length < prefix + 4) return;
        final view = ByteData.sublistView(
          Uint8List.fromList(_buffer.take(prefix + 4).toList()),
        );
        final size = prefix == 2 ? view.getUint16(0) : view.getUint32(0);
        final dataSize = view.getUint32(prefix);
        if (size < 4 ||
            size > 4 * 1024 * 1024 ||
            size != dataSize + 4 ||
            dataSize == 0) {
          throw const FormatException('Invalid Qt frame');
        }
        if (_buffer.length < size + prefix) return;
        final cipher = _buffer.sublist(prefix + 4, prefix + size);
        _buffer.removeRange(0, prefix + size);
        final plain = crypt(cipher, _key, encrypt: false);
        if (_authenticated && onData != null) {
          _lastRead = DateTime.now();
          onData!(plain);
          continue;
        }
        final payload = utf8.decode(plain);
        _lastRead = DateTime.now();
        if (!_authenticated) {
          final hello = ProtocolBeebeep.parseHelloPacket(payload);
          if (hello == null ||
              (hello['protocolVersion'] as int) < 90 ||
              (hello['datastreamVersion'] as int) < 13 ||
              ((hello['flags'] as int) & (1 << 13)) != 0 ||
              hello['auth'] !=
                  ProtocolBeebeep.authenticationHash(
                    hello['username'] as String,
                    password: password,
                  )) {
            throw const FormatException(
              'Unsupported or unauthenticated BeeBEEP HELLO',
            );
          }
          final nextKey = _keys.derive(hello['publicKey'] as String);
          _sendHello();
          _key = nextKey;
          _authenticated = true;
          peerPort = hello['port'] as int;
          onHello(hello);
          if (!ready.isCompleted) ready.complete(true);
        } else {
          final message = ProtocolBeebeep.parseMessage(payload);
          if (message == null) {
            throw const FormatException('Invalid BeeBEEP message');
          }
          if (message['header'] == ProtocolBeebeep.headerPing) {
            send(
              ProtocolBeebeep.packet(
                ProtocolBeebeep.headerPong,
                '14',
                text: '*',
              ),
            );
          } else {
            onMessage(message);
          }
        }
      }
    } catch (e) {
      close(e.toString());
    }
  }

  void close([String? reason]) {
    if (_closed) return;
    _closed = true;
    error = reason;
    _timer?.cancel();
    socket.destroy();
    _buffer.clear();
    _key.fillRange(0, _key.length, 0);
    if (!ready.isCompleted) ready.complete(false);
    onClosed();
  }
}
