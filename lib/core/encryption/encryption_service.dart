import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class EncryptionService {
  static const String _secretKey =
      'BackupDatabase2024SecretKey12345'; // 32 chars para AES-256
  static const String _ivString = 'BackupDatabaseIV'; // 16 chars para IV fixo
  static final Key _key = Key.fromUtf8(_secretKey);
  static final IV _iv = IV.fromUtf8(_ivString);

  static String encrypt(String plainText) {
    if (plainText.isEmpty) return plainText;

    // Se já parecer estar criptografada (Base64), não criptografar novamente
    if (_isBase64(plainText)) {
      // Tentar descriptografar para verificar se realmente está criptografada
      try {
        final encrypter = Encrypter(AES(_key));
        encrypter.decrypt64(plainText, iv: _iv);
        // Se chegou aqui, a senha já estava criptografada
        return plainText;
      } catch (e) {
        // Não era criptografada, é apenas um texto que parece Base64
      }
    }

    final encrypter = Encrypter(AES(_key));
    final encrypted = encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return encryptedText;

    // Se não parecer Base64, retorna como está (senha em texto plano)
    if (!_isBase64(encryptedText)) {
      return encryptedText;
    }

    // Sempre tenta descriptografar se parecer Base64
    try {
      final encrypter = Encrypter(AES(_key));
      final decrypted = encrypter.decrypt64(encryptedText, iv: _iv);

      // Se o resultado descriptografado for igual ao original, a descriptografia não funcionou
      // Isso pode acontecer se o texto não estava realmente criptografado
      if (decrypted == encryptedText) {
        return encryptedText;
      }

      return decrypted;
    } catch (e) {
      // Se falhar a descriptografia, pode ser que não seja Base64 válido
      // ou que a chave/IV estejam incorretos
      return encryptedText;
    }
  }

  static bool _isBase64(String text) {
    try {
      if (text.isEmpty) return false;

      // Base64 válido tem comprimento múltiplo de 4
      if (text.length % 4 != 0) return false;

      // Regex para Base64 válido (permite padding com =)
      final regex = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
      if (!regex.hasMatch(text)) return false;

      // Mínimo de 16 caracteres para ser uma senha criptografada (AES block)
      // Mas senhas curtas também podem ser criptografadas, então reduzimos o mínimo
      if (text.length < 8) return false;

      // Tenta fazer decode Base64 para verificar se é válido
      try {
        base64Decode(text);
        return true;
      } catch (e) {
        // Não é Base64 válido
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
