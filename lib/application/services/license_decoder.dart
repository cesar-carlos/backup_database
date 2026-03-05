import 'dart:convert';

import 'package:backup_database/core/constants/license_constants.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/license/ed25519_license_verifier.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicenseDecoder {
  LicenseDecoder({required List<int> publicKeyBytes})
    : _verifier = publicKeyBytes.length == _ed25519PublicKeySize
          ? Ed25519LicenseVerifier(publicKeyBytes: publicKeyBytes)
          : throw ArgumentError(
              'Public key must be exactly $_ed25519PublicKeySize bytes',
            );

  static const _ed25519PublicKeySize = 32;

  final Ed25519LicenseVerifier _verifier;

  static rd.Result<List<int>> _publicKeyFromEnv() {
    final base64Key = dotenv.env[LicenseConstants.envLicensePublicKey];
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
      if (decoded.length != _ed25519PublicKeySize) {
        return rd.Failure(
          core.ValidationFailure(
            message:
                'Chave pública inválida. Esperado $_ed25519PublicKeySize bytes, '
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

  static rd.Result<LicenseDecoder> fromEnv() {
    final keyResult = _publicKeyFromEnv();
    return keyResult.fold(
      (publicKeyBytes) => rd.Success(
        LicenseDecoder(publicKeyBytes: publicKeyBytes),
      ),
      rd.Failure.new,
    );
  }

  Future<rd.Result<Map<String, dynamic>>> decode(String licenseKey) async {
    try {
      final trimmedKey = licenseKey.trim();
      if (trimmedKey.isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença não pode estar vazia',
          ),
        );
      }

      final licenseBytes = _decodeBase64(trimmedKey);
      if (licenseBytes == null) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença inválida. Formato base64 incorreto.',
          ),
        );
      }

      final licenseJson = utf8.decode(licenseBytes);
      if (licenseJson.trim().isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença contém dados vazios',
          ),
        );
      }

      final licenseData = _parseJson(licenseJson);
      if (licenseData == null) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença inválida. Formato JSON incorreto.',
          ),
        );
      }

      final data = licenseData['data'];
      final signature = licenseData['signature'];

      if (data is! Map<String, dynamic> || signature == null) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença inválida. Estrutura incorreta.',
          ),
        );
      }

      final version = data['licenseVersion'] as int?;
      if (version != LicenseConstants.currentVersion) {
        return rd.Failure(
          core.ValidationFailure(
            message:
                'Versão de licença não suportada. '
                'Esperado v${LicenseConstants.currentVersion}, '
                'recebido v$version. '
                'Solicite uma licença atualizada.',
          ),
        );
      }

      return _verify(data, signature as Object);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao decodificar chave de licença',
        e,
        stackTrace,
      );
      return const rd.Failure(
        core.ValidationFailure(
          message:
              'Erro ao processar chave de licença. '
              'Verifique se a chave está correta.',
        ),
      );
    }
  }

  List<int>? _decodeBase64(String input) {
    try {
      final decoded = base64.decode(input);
      return decoded.isEmpty ? null : decoded;
    } on Object {
      return null;
    }
  }

  Map<String, dynamic>? _parseJson(String input) {
    try {
      return jsonDecode(input) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }

  rd.Result<Map<String, dynamic>> _verify(
    Map<String, dynamic> data,
    Object signature,
  ) {
    final validationResult = _validateRequiredFields(data);
    if (validationResult.isError()) {
      return validationResult;
    }

    final signatureBytesResult = _decodeSignature(signature);
    if (signatureBytesResult.isError()) {
      return rd.Failure(signatureBytesResult.exceptionOrNull()!);
    }

    final signatureBytes = signatureBytesResult.getOrNull()!;
    final dataJson = jsonEncode(data);
    final messageBytes = utf8.encode(dataJson);

    if (!_verifier.verify(
      messageBytes: messageBytes,
      signatureBytes: signatureBytes,
    )) {
      LoggerService.warning('Assinatura Ed25519 de licença inválida');
      return const rd.Failure(
        core.ValidationFailure(message: 'Assinatura de licença inválida'),
      );
    }

    final timeValidationResult = _validateTimeWindow(data);
    if (timeValidationResult.isError()) {
      return timeValidationResult;
    }

    return rd.Success(_normalizePayload(data));
  }

  rd.Result<Map<String, dynamic>> _validateRequiredFields(
    Map<String, dynamic> data,
  ) {
    final deviceKey = data['deviceKey'] as String?;
    if (deviceKey == null || deviceKey.trim().isEmpty) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Campo obrigatório ausente: deviceKey',
        ),
      );
    }

    final allowedFeatures = data['allowedFeatures'];
    if (allowedFeatures is! List) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Campo obrigatório ausente ou inválido: allowedFeatures',
        ),
      );
    }

    final issuedAt = data['issuedAt'] as String?;
    if (issuedAt == null || issuedAt.trim().isEmpty) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Campo obrigatório ausente: issuedAt',
        ),
      );
    }

    try {
      DateTime.parse(issuedAt);
    } on Object {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Campo issuedAt com formato inválido',
        ),
      );
    }

    final keyId = data['keyId'] as String?;
    if (keyId == null || keyId.trim().isEmpty) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Campo obrigatório ausente: keyId',
        ),
      );
    }
    if (keyId != LicenseConstants.keyIdDefault) {
      return rd.Failure(
        core.ValidationFailure(
          message:
              'keyId inválido. Esperado "${LicenseConstants.keyIdDefault}", '
              'recebido "$keyId".',
        ),
      );
    }

    final issuer = data['issuer'] as String?;
    if (issuer == null || issuer.trim().isEmpty) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Campo obrigatório ausente: issuer',
        ),
      );
    }

    if (issuer != LicenseConstants.issuerDefault) {
      return rd.Failure(
        core.ValidationFailure(
          message:
              'Emissor inválido. Esperado "${LicenseConstants.issuerDefault}", '
              'recebido "$issuer".',
        ),
      );
    }

    final featureValues = allowedFeatures.whereType<String>().toList();
    if (featureValues.length != allowedFeatures.length) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'allowedFeatures deve conter somente strings',
        ),
      );
    }
    final hasEmptyFeature = featureValues.any(
      (feature) => feature.trim().isEmpty,
    );
    if (hasEmptyFeature) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'allowedFeatures não pode conter valores vazios',
        ),
      );
    }

    return const rd.Success({});
  }

  rd.Result<List<int>> _decodeSignature(Object signature) {
    if (signature is! String) {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Assinatura deve ser uma string base64',
        ),
      );
    }

    try {
      final signatureBytes = base64.decode(signature);
      if (signatureBytes.isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(message: 'Assinatura vazia'),
        );
      }
      return rd.Success(signatureBytes);
    } on Object {
      return const rd.Failure(
        core.ValidationFailure(
          message: 'Assinatura inválida. Formato base64 incorreto.',
        ),
      );
    }
  }

  rd.Result<Map<String, dynamic>> _validateTimeWindow(
    Map<String, dynamic> data,
  ) {
    final now = DateTime.now();

    final notBefore = data['notBefore'] as String?;
    if (notBefore != null && notBefore.isNotEmpty) {
      try {
        final notBeforeDt = DateTime.parse(notBefore);
        if (now.isBefore(notBeforeDt)) {
          return rd.Failure(
            core.ValidationFailure(
              message:
                  'Licença ainda não válida. Válida a partir de: '
                  '${notBeforeDt.toIso8601String()}',
            ),
          );
        }
      } on Object {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Campo notBefore com formato inválido',
          ),
        );
      }
    }

    final expiresAt = data['expiresAt'] as String?;
    if (expiresAt != null && expiresAt.isNotEmpty) {
      try {
        final expiresAtDt = DateTime.parse(expiresAt);
        if (now.isAfter(expiresAtDt)) {
          return rd.Failure(
            core.ValidationFailure(
              message: 'Licença expirada em: ${expiresAtDt.toIso8601String()}',
            ),
          );
        }
      } on Object {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Campo expiresAt com formato inválido',
          ),
        );
      }
    }

    return const rd.Success({});
  }

  Map<String, dynamic> _normalizePayload(Map<String, dynamic> data) {
    final normalizedFeatures = (data['allowedFeatures'] as List)
        .map((feature) => (feature as String).trim())
        .toSet()
        .toList();
    return {
      'deviceKey': data['deviceKey'] as String,
      'expiresAt': data['expiresAt'] as String?,
      'allowedFeatures': normalizedFeatures,
    };
  }
}
