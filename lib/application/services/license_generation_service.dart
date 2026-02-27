import 'dart:convert';

import 'package:backup_database/application/services/license_decoder.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/services/i_revocation_checker.dart';
import 'package:crypto/crypto.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicenseGenerationService {
  LicenseGenerationService({
    required String secretKey,
    required LicenseDecoder licenseDecoder,
    IRevocationChecker? revocationChecker,
  })  : _secretKey = secretKey,
        _licenseDecoder = licenseDecoder,
        _revocationChecker = revocationChecker;
  final String _secretKey;
  final LicenseDecoder _licenseDecoder;
  final IRevocationChecker? _revocationChecker;

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
  ) async =>
      _licenseDecoder.decode(licenseKey);

  Future<rd.Result<License>> createLicenseFromKey({
    required String licenseKey,
    required String deviceKey,
  }) async {
    try {
      final decodeResult = await decodeLicenseKey(licenseKey);
      return await decodeResult.fold((data) async {
        if (data['deviceKey'] as String != deviceKey) {
          return const rd.Failure(
            core.ValidationFailure(
              message: 'Chave de licença não corresponde ao dispositivo',
            ),
          );
        }

        final revoked = await _revocationChecker?.isRevoked(deviceKey) ?? false;
        if (revoked) {
          LoggerService.warning('Licença rejeitada: deviceKey revogado');
          return const rd.Failure(
            core.ValidationFailure(
              message: 'Licença revogada para este dispositivo',
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
