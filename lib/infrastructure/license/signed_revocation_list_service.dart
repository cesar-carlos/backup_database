import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/license_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_revocation_checker.dart';
import 'package:backup_database/domain/services/license_signature_verifier.dart';
import 'package:backup_database/infrastructure/license/ed25519_license_verifier.dart';
import 'package:backup_database/infrastructure/license/license_public_keys.dart';
import 'package:backup_database/infrastructure/license/revocation_list_issued_at_store.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SignedRevocationListService implements IRevocationChecker {
  SignedRevocationListService({
    List<int>? publicKeyBytes,
    RevocationListIssuedAtStore? issuedAtStore,
  }) : this._(
         verifiers:
             publicKeyBytes != null &&
                 publicKeyBytes.length == LicensePublicKeys.ed25519PublicKeySize
             ? {
                 LicenseConstants.keyIdDefault: Ed25519LicenseVerifier(
                   publicKeyBytes: publicKeyBytes,
                 ),
               }
             : const {},
         issuedAtStore: issuedAtStore,
       );

  final Map<String, LicenseSignatureVerifier> _verifiers;

  Set<String>? _cachedRevokedKeys;
  DateTime? _cacheExpiresAt;
  final String? _injectedRevocationList;
  final Duration _cacheTtl;

  final RevocationListIssuedAtStore? _issuedAtStore;
  DateTime? _lastAcceptedIssuedAt;

  factory SignedRevocationListService.forTesting({
    required List<int> publicKeyBytes,
    required String revocationListJson,
    Duration cacheTtl = LicenseConstants.revocationListTtl,
    RevocationListIssuedAtStore? issuedAtStore,
    Map<String, List<int>>? publicKeysByKeyId,
  }) {
    final keys =
        publicKeysByKeyId ?? {LicenseConstants.keyIdDefault: publicKeyBytes};
    return SignedRevocationListService._(
      verifiers: {
        for (final entry in keys.entries)
          entry.key: Ed25519LicenseVerifier(publicKeyBytes: entry.value),
      },
      injectedRevocationList: revocationListJson,
      cacheTtl: cacheTtl,
      issuedAtStore: issuedAtStore,
    );
  }

  SignedRevocationListService._({
    required Map<String, LicenseSignatureVerifier> verifiers,
    this._injectedRevocationList,
    this._cacheTtl = LicenseConstants.revocationListTtl,
    this._issuedAtStore,
  }) : _verifiers = Map.unmodifiable(verifiers);

  static String? _readEnvOrNull(String key) {
    try {
      return dotenv.env[key];
    } on Object {
      return null;
    }
  }

  factory SignedRevocationListService.fromEnv({
    RevocationListIssuedAtStore? issuedAtStore,
  }) {
    final keys = LicensePublicKeys.fromEnv().getOrNull() ?? const {};
    return SignedRevocationListService._(
      verifiers: {
        for (final entry in keys.entries)
          entry.key: Ed25519LicenseVerifier(publicKeyBytes: entry.value),
      },
      issuedAtStore: issuedAtStore,
    );
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
        final shortenedTtl = _cacheTtl < const Duration(minutes: 1)
            ? _cacheTtl
            : const Duration(minutes: 1);
        _cacheExpiresAt = now.add(shortenedTtl);
        final detail = failure is Failure
            ? failure.message
            : failure.toString();
        if (_cachedRevokedKeys == null) {
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
    if (_verifiers.isEmpty) {
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

    final keyIdRaw = data['keyId'];
    final keyId = keyIdRaw is String && keyIdRaw.trim().isNotEmpty
        ? keyIdRaw.trim()
        : LicenseConstants.keyIdDefault;
    final verifier = _verifiers[keyId];
    if (verifier == null) {
      return rd.Failure(
        ValidationFailure(
          message: 'keyId desconhecido na lista de revogação: "$keyId"',
        ),
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

    final issuedAtStr = data['issuedAt'] as String?;
    DateTime? issuedAt;
    if (issuedAtStr != null) {
      try {
        issuedAt = DateTime.parse(issuedAtStr);
      } on Object {
        return const rd.Failure(
          ValidationFailure(
            message: 'issuedAt inválido na lista de revogação',
          ),
        );
      }
      final last = _lastAcceptedIssuedAt;
      if (last != null && issuedAt.isBefore(last)) {
        LoggerService.warning(
          'Lista de revogação rejeitada (rollback): issuedAt '
          '${issuedAt.toIso8601String()} < último aceito '
          '${last.toIso8601String()}',
        );
        return const rd.Failure(
          ValidationFailure(
            message: 'Tentativa de rollback de revocation list detectada',
          ),
        );
      }
    }

    if (issuedAt != null) {
      _lastAcceptedIssuedAt = issuedAt;
      final store = _issuedAtStore;
      if (store != null) {
        unawaited(_safeSaveIssuedAt(store, issuedAt));
      }
    }

    return rd.Success(keys);
  }

  Future<void> _safeSaveIssuedAt(
    RevocationListIssuedAtStore store,
    DateTime issuedAt,
  ) async {
    try {
      await store.save(issuedAt);
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao persistir lastAcceptedIssuedAt (best-effort): $e',
        e,
        s,
      );
    }
  }

  Future<void> ensureLastAcceptedIssuedAtLoaded() async {
    if (_lastAcceptedIssuedAt != null) return;
    final store = _issuedAtStore;
    if (store == null) return;
    try {
      final loaded = await store.load();
      if (loaded != null) _lastAcceptedIssuedAt = loaded;
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao carregar lastAcceptedIssuedAt do store: $e',
        e,
        s,
      );
    }
  }

  Map<String, dynamic>? _parseJson(String input) {
    try {
      return jsonDecode(input) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }
}
