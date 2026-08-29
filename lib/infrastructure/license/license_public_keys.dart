import 'dart:convert';

import 'package:backup_database/core/constants/license_constants.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicensePublicKeys {
  LicensePublicKeys._();

  static const ed25519PublicKeySize = 32;

  static String? _readEnvOrNull(String key) {
    try {
      return dotenv.env[key];
    } on Object {
      return null;
    }
  }

  static rd.Result<List<int>> legacyPublicKeyFromEnv() {
    final base64Key = _readEnvOrNull(LicenseConstants.envLicensePublicKey);
    if (base64Key == null || base64Key.trim().isEmpty) {
      return const rd.Failure(
        core.ValidationFailure(
          message:
              'Chave pública de licença não configurada. '
              'Configure BACKUP_DATABASE_LICENSE_PUBLIC_KEY.',
        ),
      );
    }
    try {
      final decoded = base64.decode(base64Key.trim());
      if (decoded.length != ed25519PublicKeySize) {
        return rd.Failure(
          core.ValidationFailure(
            message:
                'Chave pública inválida. Esperado $ed25519PublicKeySize bytes, '
                'recebido ${decoded.length} bytes.',
          ),
        );
      }
      return rd.Success(decoded);
    } on Object catch (e) {
      return rd.Failure(
        core.ValidationFailure(
          message: 'Erro ao decodificar chave pública: $e',
        ),
      );
    }
  }

  static Map<String, List<int>> publicKeysMapFromEnv() {
    final raw = _readEnvOrNull(LicenseConstants.envLicensePublicKeys);
    if (raw == null || raw.trim().isEmpty) return const {};
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw.trim()) as Map<String, dynamic>;
    } on Object catch (e) {
      LoggerService.warning(
        'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS com JSON inválido: $e. '
        'Ignorando esse env e mantendo apenas chave legacy se houver.',
      );
      return const {};
    }
    final result = <String, List<int>>{};
    decoded.forEach((keyId, value) {
      if (value is! String) {
        LoggerService.warning(
          'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS: entry "$keyId" '
          'não é string base64 — ignorada.',
        );
        return;
      }
      try {
        final bytes = base64.decode(value.trim());
        if (bytes.length != ed25519PublicKeySize) {
          LoggerService.warning(
            'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS: entry "$keyId" tem '
            '${bytes.length} bytes (esperado $ed25519PublicKeySize) — '
            'ignorada.',
          );
          return;
        }
        result[keyId] = bytes;
      } on Object catch (e) {
        LoggerService.warning(
          'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS: entry "$keyId" base64 '
          'inválido ($e) — ignorada.',
        );
      }
    });
    return result;
  }

  /// Mescla `PUBLIC_KEY` (como [LicenseConstants.keyIdDefault]) com
  /// `PUBLIC_KEYS`. O mapa JSON tem precedência em colisão de `keyId`.
  static rd.Result<Map<String, List<int>>> fromEnv() {
    final keys = <String, List<int>>{};

    final legacy = legacyPublicKeyFromEnv();
    legacy.fold(
      (bytes) => keys[LicenseConstants.keyIdDefault] = bytes,
      (_) {},
    );

    keys.addAll(publicKeysMapFromEnv());

    if (keys.isEmpty) {
      return rd.Failure(legacy.exceptionOrNull()!);
    }

    return rd.Success(Map.unmodifiable(keys));
  }
}
