import 'dart:convert';
import 'dart:typed_data';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/sic.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import 'package:pointycastle/stream/sic.dart';

class EncryptionService {
  EncryptionService();

  static const String _legacySecretKey = 'BackupDatabase2024SecretKey12345';
  static const String _ivString = 'BackupDatabaseIV';
  static const int _aesKeyLengthBytes = 32;

  static final Uint8List _ivBytes = Uint8List.fromList(utf8.encode(_ivString));
  static final Uint8List _legacyKeyBytes = Uint8List.fromList(
    utf8.encode(_legacySecretKey),
  );

  static Uint8List? _derivedKeyBytes;
  static String _currentKeySource = 'legacy';

  static Uint8List get _currentKeyBytes => _derivedKeyBytes ?? _legacyKeyBytes;

  static void initializeWithDeviceKey(String deviceKey) {
    final keyBytes = utf8.encode(deviceKey);
    final keyHash = sha256.convert(keyBytes);
    _derivedKeyBytes = Uint8List.fromList(
      keyHash.bytes.sublist(0, _aesKeyLengthBytes),
    );
    _currentKeySource = 'device';
    LoggerService.info(
      'EncryptionService initialized with device-specific key',
    );
  }

  @visibleForTesting
  static void resetToLegacy() {
    _derivedKeyBytes = null;
    _currentKeySource = 'legacy';
  }

  static String encrypt(String plainText) {
    if (plainText.isEmpty) return plainText;

    if (_looksEncrypted(plainText)) return plainText;

    final encrypted = _process(
      forEncryption: true,
      keyBytes: _currentKeyBytes,
      data: Uint8List.fromList(utf8.encode(plainText)),
    );
    return base64Encode(encrypted);
  }

  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return encryptedText;

    if (!_looksLikeBase64(encryptedText)) return encryptedText;

    try {
      return _decryptWithKey(_currentKeyBytes, encryptedText);
    } on Object catch (_) {
      try {
        return _decryptWithKey(_legacyKeyBytes, encryptedText);
      } on Object catch (_) {
        return encryptedText;
      }
    }
  }

  static bool _looksEncrypted(String text) {
    if (!_looksLikeBase64(text)) return false;
    try {
      _decryptWithKey(_currentKeyBytes, text);
      return true;
    } on Object catch (_) {
      try {
        _decryptWithKey(_legacyKeyBytes, text);
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

  static String _decryptWithKey(Uint8List keyBytes, String encryptedText) {
    final decrypted = _process(
      forEncryption: false,
      keyBytes: keyBytes,
      data: base64Decode(encryptedText),
    );
    return utf8.decode(decrypted);
  }

  static Uint8List _process({
    required bool forEncryption,
    required Uint8List keyBytes,
    required Uint8List data,
  }) {
    final aes = AESEngine();
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      SICBlockCipher(aes.blockSize, SICStreamCipher(aes)),
    );
    cipher.init(
      forEncryption,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), _ivBytes),
        null,
      ),
    );
    return cipher.process(data);
  }
}
