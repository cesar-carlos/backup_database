import 'dart:convert';

import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:crypto/crypto.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicenseGenerationService {
  LicenseGenerationService({required String secretKey})
    : _secretKey = secretKey;
  final String _secretKey;

  Future<rd.Result<String>> generateLicenseKey({
    required String deviceKey,
    required List<String> allowedFeatures,
    DateTime? expiresAt,
  }) async {
    try {
      final data = {
        'deviceKey': deviceKey,
        'expiresAt': expiresAt?.toIso8601String(),
        'allowedFeatures': allowedFeatures,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final jsonString = jsonEncode(data);
      final bytes = utf8.encode(jsonString);
      final keyBytes = utf8.encode(_secretKey);

      final hmac = Hmac(sha256, keyBytes);
      final digest = hmac.convert(bytes);

      final licenseData = {'data': data, 'signature': digest.toString()};

      final licenseJson = jsonEncode(licenseData);
      final licenseBytes = utf8.encode(licenseJson);
      final licenseBase64 = base64.encode(licenseBytes);

      return rd.Success(licenseBase64);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao gerar chave de licença', e, stackTrace);
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao gerar chave de licença: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<Map<String, dynamic>>> decodeLicenseKey(
    String licenseKey,
  ) async {
    try {
      final trimmedKey = licenseKey.trim();
      if (trimmedKey.isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença não pode estar vazia',
          ),
        );
      }

      List<int> licenseBytes;
      try {
        licenseBytes = base64.decode(trimmedKey);
      } on Object catch (e) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença inválida. Formato base64 incorreto.',
          ),
        );
      }

      if (licenseBytes.isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença vazia após decodificação',
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

      Map<String, dynamic> licenseData;
      try {
        licenseData = jsonDecode(licenseJson) as Map<String, dynamic>;
      } on Object catch (e) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'Chave de licença inválida. Formato JSON incorreto.',
          ),
        );
      }

      final data = licenseData['data'] as Map<String, dynamic>;
      final signature = licenseData['signature'] as String;

      final dataJson = jsonEncode(data);
      final dataBytes = utf8.encode(dataJson);
      final keyBytes = utf8.encode(_secretKey);

      final hmac = Hmac(sha256, keyBytes);
      final expectedSignature = hmac.convert(dataBytes).toString();

      if (signature != expectedSignature) {
        LoggerService.warning('Assinatura de licença inválida');
        return const rd.Failure(
          core.ValidationFailure(message: 'Assinatura de licença inválida'),
        );
      }

      return rd.Success(data);
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

  Future<rd.Result<License>> createLicenseFromKey({
    required String licenseKey,
    required String deviceKey,
  }) async {
    try {
      final decodeResult = await decodeLicenseKey(licenseKey);
      return decodeResult.fold((data) {
        if (data['deviceKey'] as String != deviceKey) {
          return const rd.Failure(
            core.ValidationFailure(
              message: 'Chave de licença não corresponde ao dispositivo',
            ),
          );
        }

        final expiresAtStr = data['expiresAt'] as String?;
        final expiresAt = expiresAtStr != null
            ? DateTime.parse(expiresAtStr)
            : null;

        final allowedFeatures = (data['allowedFeatures'] as List)
            .cast<String>()
            .toList();

        final license = License(
          deviceKey: deviceKey,
          licenseKey: licenseKey,
          expiresAt: expiresAt,
          allowedFeatures: allowedFeatures,
        );

        return rd.Success(license);
      }, rd.Failure.new);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao criar licença a partir da chave',
        e,
        stackTrace,
      );
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao criar licença: $e',
          originalError: e,
        ),
      );
    }
  }
}
