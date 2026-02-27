import 'dart:convert';

import 'package:backup_database/core/constants/license_constants.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/license/ed25519_license_verifier.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicenseDecoder {
  LicenseDecoder({
    required String v1SecretKey,
    List<int>? v2PublicKeyBytes,
  })  : _v1SecretKey = v1SecretKey,
        _v2Verifier = v2PublicKeyBytes != null &&
                v2PublicKeyBytes.length == _ed25519PublicKeySize
            ? Ed25519LicenseVerifier(publicKeyBytes: v2PublicKeyBytes)
            : null;

  static const _ed25519PublicKeySize = 32;

  final String _v1SecretKey;
  final Ed25519LicenseVerifier? _v2Verifier;

  static List<int>? _publicKeyFromEnv() {
    final base64Key = dotenv.env[LicenseConstants.envLicensePublicKey];
    if (base64Key == null || base64Key.trim().isEmpty) {
      return null;
    }
    try {
      return base64.decode(base64Key.trim());
    } on Object {
      return null;
    }
  }

  factory LicenseDecoder.fromEnv({
    required String v1SecretKey,
  }) {
    final v2Key = _publicKeyFromEnv();
    return LicenseDecoder(
      v1SecretKey: v1SecretKey,
      v2PublicKeyBytes: v2Key,
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

      final version = data['licenseVersion'] as int? ?? LicenseConstants.version1;

      if (version == LicenseConstants.version2) {
        return _verifyV2(data, signature as Object);
      }

      return _verifyV1(data, signature as Object);
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

  rd.Result<Map<String, dynamic>> _verifyV2(
    Map<String, dynamic> data,
    Object signature,
  ) {
    final verifier = _v2Verifier;
    if (verifier == null) {
      LoggerService.warning(
        'Licença v2 recebida mas chave pública não configurada',
      );
      return const rd.Failure(
        core.ValidationFailure(
          message:
              'Licença v2 requer chave pública. '
              'Configure BACKUP_DATABASE_LICENSE_PUBLIC_KEY.',
        ),
      );
    }

    List<int> signatureBytes;
    if (signature is String) {
      try {
        signatureBytes = base64.decode(signature);
      } on Object {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Assinatura v2 inválida. Formato base64 incorreto.',
          ),
        );
      }
    } else {
      return const rd.Failure(
        core.ValidationFailure(message: 'Assinatura v2 inválida'),
      );
    }

    final dataJson = jsonEncode(data);
    final messageBytes = utf8.encode(dataJson);

    if (!verifier.verify(
      messageBytes: messageBytes,
      signatureBytes: signatureBytes,
    )) {
      LoggerService.warning('Assinatura Ed25519 de licença inválida');
      return const rd.Failure(
        core.ValidationFailure(message: 'Assinatura de licença inválida'),
      );
    }

    final notBefore = data['notBefore'] as String?;
    if (notBefore != null) {
      try {
        final notBeforeDt = DateTime.parse(notBefore);
        if (DateTime.now().isBefore(notBeforeDt)) {
          return const rd.Failure(
            core.ValidationFailure(
              message: 'Licença ainda não válida (notBefore)',
            ),
          );
        }
      } on Object {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Licença v2: notBefore inválido',
          ),
        );
      }
    }

    return rd.Success(_normalizePayload(data));
  }

  rd.Result<Map<String, dynamic>> _verifyV1(
    Map<String, dynamic> data,
    Object signature,
  ) {
    if (signature is! String) {
      return const rd.Failure(
        core.ValidationFailure(message: 'Assinatura v1 inválida'),
      );
    }

    final dataJson = jsonEncode(data);
    final dataBytes = utf8.encode(dataJson);
    final keyBytes = utf8.encode(_v1SecretKey);

    final hmac = Hmac(sha256, keyBytes);
    final expectedSignature = hmac.convert(dataBytes).toString();

    if (signature != expectedSignature) {
      LoggerService.warning('Assinatura HMAC de licença inválida');
      return const rd.Failure(
        core.ValidationFailure(message: 'Assinatura de licença inválida'),
      );
    }

    return rd.Success(_normalizePayload(data));
  }

  Map<String, dynamic> _normalizePayload(Map<String, dynamic> data) {
    return {
      'deviceKey': data['deviceKey'] as String,
      'expiresAt': data['expiresAt'] as String?,
      'allowedFeatures': (data['allowedFeatures'] as List?)?.cast<String>() ??
          <String>[],
    };
  }
}
