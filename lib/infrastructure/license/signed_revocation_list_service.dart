import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/license_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_revocation_checker.dart';
import 'package:backup_database/infrastructure/license/ed25519_license_verifier.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SignedRevocationListService implements IRevocationChecker {
  SignedRevocationListService({
    List<int>? publicKeyBytes,
  }) : this._(publicKeyBytes: publicKeyBytes);

  static const _ed25519PublicKeySize = 32;

  final Ed25519LicenseVerifier? _verifier;

  Set<String>? _cachedRevokedKeys;
  DateTime? _cacheExpiresAt;
  final String? _injectedRevocationList;
  final Duration _cacheTtl;

  factory SignedRevocationListService.forTesting({
    required List<int> publicKeyBytes,
    required String revocationListJson,
    Duration cacheTtl = LicenseConstants.revocationListTtl,
  }) => SignedRevocationListService._(
    publicKeyBytes: publicKeyBytes,
    injectedRevocationList: revocationListJson,
    cacheTtl: cacheTtl,
  );

  SignedRevocationListService._({
    List<int>? publicKeyBytes,
    String? injectedRevocationList,
    Duration cacheTtl = LicenseConstants.revocationListTtl,
  }) : _verifier =
           publicKeyBytes != null &&
               publicKeyBytes.length == _ed25519PublicKeySize
           ? Ed25519LicenseVerifier(publicKeyBytes: publicKeyBytes)
           : null,
       _injectedRevocationList = injectedRevocationList,
       _cacheTtl = cacheTtl;

  static String? _readEnvOrNull(String key) {
    try {
      return dotenv.env[key];
    } on Object {
      // Tests and some runtime paths may use this service before dotenv is loaded.
      return null;
    }
  }

  static List<int>? _publicKeyFromEnv() {
    final base64Key = _readEnvOrNull(LicenseConstants.envLicensePublicKey);
    if (base64Key == null || base64Key.trim().isEmpty) {
      return null;
    }
    try {
      return base64.decode(base64Key.trim());
    } on Object {
      return null;
    }
  }

  factory SignedRevocationListService.fromEnv() {
    final keyBytes = _publicKeyFromEnv();
    return SignedRevocationListService(publicKeyBytes: keyBytes);
  }

  @override
  Future<bool> isRevoked(String deviceKey) async {
    final revoked = await _getRevokedDeviceKeys();
    final isRevoked = revoked.contains(deviceKey);
    if (isRevoked) {
      LoggerService.warning(
        'Device key revoked: $deviceKey (from cached revocation list)',
      );
    }
    return isRevoked;
  }

  Future<Set<String>> _getRevokedDeviceKeys() async {
    final now = DateTime.now();
    final cacheValid =
        _cacheExpiresAt != null && now.isBefore(_cacheExpiresAt!);

    if (cacheValid && _cachedRevokedKeys != null) {
      return _cachedRevokedKeys!;
    }

    final raw = await _loadRevocationListRaw();
    if (raw == null || raw.isEmpty) {
      // Sem fonte de revogação configurada: nada a aplicar. Anota
      // explicitamente no log a primeira vez para a operação ter
      // ciência de que não há enforcement remoto.
      if (_cachedRevokedKeys == null) {
        LoggerService.info(
          'Sem fonte de revogação configurada — nenhum deviceKey '
          'considerado revogado.',
        );
      }
      _cacheExpiresAt = now.add(_cacheTtl);
      _cachedRevokedKeys ??= {};
      return _cachedRevokedKeys!;
    }

    final result = _parseAndVerify(raw);
    result.fold(
      (keys) {
        _cachedRevokedKeys = keys;
        _cacheExpiresAt = now.add(_cacheTtl);
        LoggerService.info(
          'Lista de revogação carregada: ${keys.length} deviceKey(s), '
          'cache válido até ${_cacheExpiresAt!.toIso8601String()}',
        );
      },
      (failure) {
        // FIX: antes esta ramificação fazia `_cachedRevokedKeys ??= {}`,
        // o que era fail-OPEN (atacante corrompia a lista → nenhum
        // device aparecia revogado). Agora preservamos o último
        // `_cachedRevokedKeys` válido, e só caímos para set vazio se
        // jamais carregamos uma lista boa antes (estado inicial).
        // A operação fica com o último snapshot bom até a próxima
        // tentativa (cache TTL menor para acelerar recuperação).
        final shortenedTtl =
            _cacheTtl < const Duration(minutes: 1)
                ? _cacheTtl
                : const Duration(minutes: 1);
        _cacheExpiresAt = now.add(shortenedTtl);
        // Antes interpolava `$failure` direto na string — para `Failure`
        // gerava `Failure(message: ..., code: null)` no log. Extraímos
        // `.message` quando é Failure (caso comum aqui — o
        // `_parseAndVerify` sempre retorna `ValidationFailure`).
        final detail = failure is Failure ? failure.message : failure.toString();
        if (_cachedRevokedKeys == null) {
          // Nunca tivemos um snapshot bom — fail-CLOSED não é viável
          // sem quebrar o fluxo, então logamos de forma conspícua.
          _cachedRevokedKeys = {};
          LoggerService.error(
            'Lista de revogação inválida e sem snapshot anterior em cache: '
            '$detail. Operando SEM enforcement de revogação até a próxima '
            'tentativa em ${shortenedTtl.inSeconds}s.',
          );
        } else {
          LoggerService.warning(
            'Lista de revogação inválida ($detail) — preservando snapshot '
            'anterior (${_cachedRevokedKeys!.length} chaves) por '
            '${shortenedTtl.inSeconds}s.',
          );
        }
      },
    );
    return _cachedRevokedKeys!;
  }

  Future<String?> _loadRevocationListRaw() async {
    if (_injectedRevocationList != null) {
      return _injectedRevocationList;
    }
    final fromEnv = _readEnvOrNull(LicenseConstants.envRevocationList);
    if (fromEnv != null && fromEnv.trim().isNotEmpty) {
      try {
        return utf8.decode(base64.decode(fromEnv.trim()));
      } on Object {
        return fromEnv.trim();
      }
    }

    final path = _readEnvOrNull(LicenseConstants.envRevocationListPath);
    if (path != null && path.trim().isNotEmpty) {
      try {
        final file = File(path.trim());
        if (await file.exists()) {
          return await file.readAsString();
        }
      } on Object catch (e) {
        LoggerService.warning('Erro ao ler arquivo de revogação: $e');
      }
    }
    return null;
  }

  rd.Result<Set<String>> _parseAndVerify(String raw) {
    final verifier = _verifier;
    if (verifier == null) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Chave pública não configurada para verificar lista',
        ),
      );
    }

    final parsed = _parseJson(raw);
    if (parsed == null) {
      return const rd.Failure(
        ValidationFailure(message: 'Formato JSON inválido'),
      );
    }

    final data = parsed['data'];
    final signature = parsed['signature'];

    if (data is! Map<String, dynamic> || signature == null) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Estrutura esperada: data + signature',
        ),
      );
    }

    List<int> signatureBytes;
    if (signature is String) {
      try {
        signatureBytes = base64.decode(signature);
      } on Object {
        return const rd.Failure(
          ValidationFailure(message: 'Assinatura base64 inválida'),
        );
      }
    } else {
      return const rd.Failure(
        ValidationFailure(message: 'Assinatura inválida'),
      );
    }

    final dataJson = jsonEncode(data);
    final messageBytes = utf8.encode(dataJson);

    if (!verifier.verify(
      messageBytes: messageBytes,
      signatureBytes: signatureBytes,
    )) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Assinatura da lista de revogação inválida',
        ),
      );
    }

    final keys =
        (data['revokedDeviceKeys'] as List?)?.whereType<String>().toSet() ?? {};

    final expiresAtStr = data['expiresAt'] as String?;
    if (expiresAtStr != null) {
      try {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (DateTime.now().isAfter(expiresAt)) {
          return const rd.Failure(
            ValidationFailure(
              message: 'Lista de revogação expirada',
            ),
          );
        }
      } on Object {
        return const rd.Failure(
          ValidationFailure(
            message: 'expiresAt inválido na lista de revogação',
          ),
        );
      }
    }

    return rd.Success(keys);
  }

  Map<String, dynamic>? _parseJson(String input) {
    try {
      return jsonDecode(input) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }
}
