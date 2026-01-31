import 'dart:convert';
import 'dart:typed_data';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class EncryptionService {
  EncryptionService();

  static const String _legacySecretKey = 'BackupDatabase2024SecretKey12345';
  static const String _ivString = 'BackupDatabaseIV';

  static final IV _iv = IV.fromUtf8(_ivString);

  static Key? _derivedKey;
  static final Key _legacyKey = Key.fromUtf8(_legacySecretKey);
  static final Encrypter _legacyEncrypter = Encrypter(AES(_legacyKey));
  static Encrypter? _currentEncrypter;

  static String _currentKeySource = 'legacy';

  static void initializeWithDeviceKey(String deviceKey) {
    final keyBytes = utf8.encode(deviceKey);
    final keyHash = sha256.convert(keyBytes);
    _derivedKey = Key(Uint8List.fromList(keyHash.bytes.sublist(0, 32)));
    _currentEncrypter = Encrypter(AES(_derivedKey!));
    _currentKeySource = 'device';
    LoggerService.info(
      'EncryptionService initialized with device-specific key',
    );
  }

  static Encrypter get _encrypter {
    return _currentEncrypter ?? _legacyEncrypter;
  }

  static String encrypt(String plainText) {
    if (plainText.isEmpty) return plainText;

    if (_looksEncrypted(plainText)) return plainText;

    final encrypted = _encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return encryptedText;

    if (!_looksLikeBase64(encryptedText)) return encryptedText;

    try {
      return _encrypter.decrypt64(encryptedText, iv: _iv);
    } on Object catch (_) {
      try {
        return _legacyEncrypter.decrypt64(encryptedText, iv: _iv);
      } on Object catch (_) {
        return encryptedText;
      }
    }
  }

  static bool _looksEncrypted(String text) {
    if (!_looksLikeBase64(text)) return false;
    try {
      _encrypter.decrypt64(text, iv: _iv);
      return true;
    } on Object catch (_) {
      try {
        _legacyEncrypter.decrypt64(text, iv: _iv);
        return true;
      } on Object catch (_) {
        return false;
      }
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
    } on Object catch (_) {
      return false;
    }
  }

  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static String getKeySource() => _currentKeySource;
}
