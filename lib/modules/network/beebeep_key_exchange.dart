import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/digests/sha3.dart';

/// BeeBEEP ECDH.cpp wire format: sect163k1, little-endian x/y (24 bytes
/// each), decimal colon-separated public key; shared bytes are concatenated
/// as decimal text then base64url encoded before SHA3-256.
class BeebeepKeyExchange {
  static final _one = BigInt.one;
  static final _polynomial = (_one << 163) | BigInt.from(0xc9);
  static final _order = BigInt.parse(
    '4000000000000000000020108a2e0cc0d99f8a5ef',
    radix: 16,
  );
  static final _generator = (
    BigInt.parse('2fe13c0537bbc11acaa07d793de4e6d5e5c94eee8', radix: 16),
    BigInt.parse('289070fb05d38ff58321f2e800536d538ccdaa3d9', radix: 16),
  );
  late final BigInt _private;
  late final String publicKey;

  BeebeepKeyExchange() {
    final random = Random.secure();
    do {
      _privateCandidate =
          BigInt.parse(
            List.generate(
              21,
              (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
            ).join(),
            radix: 16,
          ) &
          ((_one << 162) - _one);
    } while (_privateCandidate == BigInt.zero);
    _private = _privateCandidate;
    publicKey = _encode(_multiply(_generator, _private)!).join(':');
  }
  BigInt _privateCandidate = BigInt.zero;

  Uint8List derive(String remote) {
    final values = remote.split(':').map(int.parse).toList();
    if (values.length != 48 || values.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Invalid BeeBEEP public key');
    }
    BigInt decode(List<int> bytes) => BigInt.parse(
      bytes.reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    final point = (decode(values.sublist(0, 24)), decode(values.sublist(24)));
    final (x, y) = point;
    if (x.bitLength > 163 ||
        y.bitLength > 163 ||
        x == BigInt.zero ||
        (_mul(y, y) ^ _mul(x, y)) !=
            (_mul(_mul(x, x), x) ^ _mul(x, x) ^ _one) ||
        _multiply(point, _order) != null) {
      throw const FormatException('Invalid BeeBEEP curve point');
    }
    final shared = _multiply(point, _private);
    if (shared == null) throw const FormatException('Empty shared key');
    final encoded = base64Url
        .encode(utf8.encode(_encode(shared).join()))
        .replaceAll('=', '');
    return SHA3Digest(256).process(Uint8List.fromList(utf8.encode(encoded)));
  }

  static List<int> _encode((BigInt, BigInt) point) => [
    for (final coordinate in [point.$1, point.$2])
      for (var i = 0; i < 24; i++)
        ((coordinate >> (i * 8)) & BigInt.from(255)).toInt(),
  ];
  static BigInt _mul(BigInt a, BigInt b) {
    var result = BigInt.zero;
    while (b != BigInt.zero) {
      if (b.isOdd) result ^= a;
      b >>= 1;
      a <<= 1;
      if (a.bitLength > 163) a ^= _polynomial;
    }
    return result;
  }

  static BigInt _inverse(BigInt a) {
    if (a == BigInt.zero) throw const FormatException('Zero divisor');
    var b = _polynomial, u = _one, v = BigInt.zero;
    while (a != _one) {
      var shift = a.bitLength - b.bitLength;
      if (shift < 0) {
        final t = a;
        a = b;
        b = t;
        final s = u;
        u = v;
        v = s;
        shift = -shift;
      }
      a ^= b << shift;
      u ^= v << shift;
    }
    return u;
  }

  static (BigInt, BigInt)? _add((BigInt, BigInt)? p, (BigInt, BigInt)? q) {
    if (p == null) return q;
    if (q == null) return p;
    final (x, y) = p;
    final (xx, yy) = q;
    if (x == xx) {
      if (y != yy || x == BigInt.zero) return null;
      final s = x ^ _mul(y, _inverse(x));
      final nx = _mul(s, s) ^ s ^ _one;
      return (nx, _mul(x, x) ^ _mul(s ^ _one, nx));
    }
    final s = _mul(y ^ yy, _inverse(x ^ xx));
    final nx = _mul(s, s) ^ s ^ x ^ xx ^ _one;
    return (nx, _mul(s, x ^ nx) ^ nx ^ y);
  }

  static (BigInt, BigInt)? _multiply((BigInt, BigInt) point, BigInt scalar) {
    (BigInt, BigInt)? result;
    (BigInt, BigInt)? current = point;
    while (scalar != BigInt.zero) {
      if (scalar.isOdd) result = _add(result, current);
      current = _add(current, current);
      scalar >>= 1;
    }
    return result;
  }
}
