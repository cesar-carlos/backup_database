import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class EncryptionService {
  static const String _secretKey = 'BackupDatabase2024SecretKey12345';
  static const String _ivString = 'BackupDatabaseIV';

  static final Key _key = Key.fromUtf8(_secretKey);
  static final IV _iv = IV.fromUtf8(_ivString);
  static final Encrypter _encrypter = Encrypter(AES(_key));

  static String encrypt(String plainText) {
    if (plainText.isEmpty) return plainText;

    if (_looksEncrypted(plainText)) return plainText;

    final encrypted = _encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return encryptedText;

    try {
      if (!_looksLikeBase64(encryptedText)) return encryptedText;
      return _encrypter.decrypt64(encryptedText, iv: _iv);
    } catch (_) {
      return encryptedText;
    }
  }

  static bool _looksEncrypted(String text) {
    if (!_looksLikeBase64(text)) return false;
    try {
      _encrypter.decrypt64(text, iv: _iv);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _looksLikeBase64(String text) {
    if (text.isEmpty) return false;
    if (text.length < 8) return false;
    if (text.length % 4 != 0) return false;

    final isBase64Charset = RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(text);
    if (!isBase64Charset) return false;

    try {
      base64Decode(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
