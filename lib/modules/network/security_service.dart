import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class SecurityService {
  bool isEncryptionEnabled = false;
  String _password = '';
  String get password => _password;
  enc.Key? _key;
  enc.IV? _iv;
  enc.Encrypter? _encrypter;

  SecurityService() {
    _updateKey();
  }

  void setPassword(String password) {
    _password = password;
    _updateKey();
  }

  void _updateKey() {
    // Tạo khóa 256-bit (32 bytes) từ SHA-256 của password
    final digest = sha256.convert(utf8.encode(_password));
    _key = enc.Key(Uint8List.fromList(digest.bytes));
    // IV 16 bytes cố định từ 16 bytes đầu của khóa (hoặc dùng CBC với IV)
    _iv = enc.IV(Uint8List.fromList(digest.bytes.sublist(0, 16)));
    _encrypter = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.cbc));
  }

  /// Mã hóa chuỗi nếu tính năng mã hóa được bật
  String encrypt(String plainText) {
    if (!isEncryptionEnabled || _encrypter == null || _iv == null) {
      return plainText;
    }
    try {
      final encrypted = _encrypter!.encrypt(plainText, iv: _iv!);
      return 'ENC:${encrypted.base64}';
    } catch (_) {
      return plainText;
    }
  }

  /// Giải mã chuỗi
  String decrypt(String cipherText) {
    if (!cipherText.startsWith('ENC:') || _encrypter == null || _iv == null) {
      return cipherText;
    }
    try {
      final base64Str = cipherText.substring(4);
      return _encrypter!.decrypt64(base64Str, iv: _iv!);
    } catch (_) {
      return cipherText;
    }
  }
}
