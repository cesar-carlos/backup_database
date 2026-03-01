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
  bool _loadAttempted = false;
  final String? _injectedRevocationList;

  factory SignedRevocationListService.forTesting({
    required List<int> publicKeyBytes,
    required String revocationListJson,
  }) => SignedRevocationListService._(
    publicKeyBytes: publicKeyBytes,
    injectedRevocationList: revocationListJson,
  );

  SignedRevocationListService._({
    List<int>? publicKeyBytes,
    String? injectedRevocationList,
  }) : _verifier =
           publicKeyBytes != null &&
               publicKeyBytes.length == _ed25519PublicKeySize
           ? Ed25519LicenseVerifier(publicKeyBytes: publicKeyBytes)
           : null,
       _injectedRevocationList = injectedRevocationList;

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
    return revoked.contains(deviceKey);
  }

  Future<Set<String>> _getRevokedDeviceKeys() async {
    if (_loadAttempted) {
      return _cachedRevokedKeys ?? {};
    }
    _loadAttempted = true;

    final raw = await _loadRevocationListRaw();
    if (raw == null || raw.isEmpty) {
      return {};
    }

    final result = _parseAndVerify(raw);
    result.fold(
      (keys) {
        _cachedRevokedKeys = keys;
        LoggerService.info(
          'Lista de revogação carregada: ${keys.length} deviceKey(s)',
        );
      },
      (failure) {
        LoggerService.warning(
          'Lista de revogação inválida ou não verificada: $failure',
        );
      },
    );
    return _cachedRevokedKeys ?? {};
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
