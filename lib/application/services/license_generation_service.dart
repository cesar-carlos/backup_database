import 'dart:convert';
import 'dart:typed_data';

import 'package:backup_database/application/services/license_decoder.dart';
import 'package:backup_database/application/services/revocation_check_helper.dart';
import 'package:backup_database/core/constants/license_constants.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/string_field_validator.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/services/i_revocation_checker.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:result_dart/result_dart.dart' as rd;

class LicenseGenerationService {
  LicenseGenerationService({
    required LicenseDecoder licenseDecoder,
    List<int>? privateKeyBytes,
    IRevocationChecker? revocationChecker,
    String activeKeyId = LicenseConstants.keyIdDefault,
  }) : _privateKey = privateKeyBytes == null
           ? null
           : ed.PrivateKey(privateKeyBytes),
       _licenseDecoder = licenseDecoder,
       _revocationChecker = revocationChecker,
       _activeKeyId = activeKeyId;

  final ed.PrivateKey? _privateKey;
  final LicenseDecoder _licenseDecoder;
  final IRevocationChecker? _revocationChecker;

  /// `keyId` que vai no payload das licenças geradas. Deve casar com a
  /// public key correspondente registrada no [LicenseDecoder] do cliente
  /// (caso contrário a licença é rejeitada com "keyId desconhecido").
  final String _activeKeyId;

  bool get canGenerateLocally => _privateKey != null;

  /// `keyId` atualmente usado para assinar novas licenças. Útil em UI
  /// administrativa para mostrar qual chave está sendo emitida.
  String get activeKeyId => _activeKeyId;

  Future<rd.Result<String>> generateLicenseKey({
    required String deviceKey,
    required List<String> allowedFeatures,
    DateTime? expiresAt,
    DateTime? notBefore,
  }) async {
    try {
      if (!canGenerateLocally) {
        return const rd.Failure(
          core.ValidationFailure(
            message:
                'Geração local indisponível. Configure a chave privada '
                'somente em ambiente debug/admin.',
          ),
        );
      }

      // Texto agora padronizado em "não pode ser vazio" (helper canônico)
      // — variação minor vs antiga "estar vazio". Nenhum teste verificava
      // a wording exata.
      final deviceKeyFailure = StringFieldValidator.requireNonBlank(
        value: deviceKey,
        fieldLabel: 'deviceKey',
      );
      if (deviceKeyFailure != null) return rd.Failure(deviceKeyFailure);

      if (allowedFeatures.isEmpty) {
        return const rd.Failure(
          core.ValidationFailure(
            message: 'allowedFeatures não pode estar vazio',
          ),
        );
      }

      final now = DateTime.now();
      final data = {
        'licenseVersion': LicenseConstants.currentVersion,
        'deviceKey': deviceKey.trim(),
        'allowedFeatures': allowedFeatures,
        'issuedAt': now.toIso8601String(),
        // Antes hard-codava `keyIdDefault`. Agora usa o `activeKeyId`
        // do service — permite rotação sem rebuild do app: basta
        // configurar `BACKUP_DATABASE_LICENSE_ACTIVE_KEY_ID` no env.
        'keyId': _activeKeyId,
        'issuer': LicenseConstants.issuerDefault,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
        if (notBefore != null) 'notBefore': notBefore.toIso8601String(),
      };

      final dataJson = jsonEncode(data);
      final messageBytes = Uint8List.fromList(utf8.encode(dataJson));
      final signatureBytes = ed.sign(_privateKey!, messageBytes);

      final licenseData = {
        'data': data,
        'signature': base64.encode(signatureBytes),
      };

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
  ) async => _licenseDecoder.decode(licenseKey);

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

        final revoked = await RevocationCheckHelper.isRevokedSafe(
          _revocationChecker,
          deviceKey,
          caller: 'createLicenseFromKey',
        );
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

        final notBeforeStr = data['notBefore'] as String?;
        final notBefore = notBeforeStr != null
            ? DateTime.parse(notBeforeStr)
            : null;

        final allowedFeatures = (data['allowedFeatures'] as List)
            .cast<String>()
            .toList();

        final license = License(
          deviceKey: deviceKey,
          licenseKey: licenseKey,
          expiresAt: expiresAt,
          notBefore: notBefore,
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
