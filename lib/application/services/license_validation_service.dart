import 'package:backup_database/application/services/revocation_check_helper.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/domain/services/i_revocation_checker.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicenseValidationService implements ILicenseValidationService {
  LicenseValidationService({
    required ILicenseRepository licenseRepository,
    required IDeviceKeyService deviceKeyService,
    IRevocationChecker? revocationChecker,
  }) : _licenseRepository = licenseRepository,
       _deviceKeyService = deviceKeyService,
       _revocationChecker = revocationChecker;
  final ILicenseRepository _licenseRepository;
  final IDeviceKeyService _deviceKeyService;
  final IRevocationChecker? _revocationChecker;

  @override
  Future<rd.Result<License>> getCurrentLicense() async {
    try {
      final deviceKeyResult = await _deviceKeyService.getDeviceKey();
      return await deviceKeyResult.fold(
        (deviceKey) async {
          // Paraleliza a busca da licença e a checagem de revogação.
          // Antes eram sequenciais; cada uma pode envolver I/O (DB local
          // + leitura/parse da revocation list).
          final results = await Future.wait<Object>([
            _licenseRepository.getByDeviceKey(deviceKey),
            RevocationCheckHelper.isRevokedSafe(
              _revocationChecker,
              deviceKey,
              caller: 'getCurrentLicense',
            ),
          ]);
          final licenseResult = results[0] as rd.Result<License>;
          final revoked = results[1] as bool;

          return licenseResult.fold(
            (license) async {
              if (license.isExpired) {
                LoggerService.warning('Licença encontrada mas expirada');
                return const rd.Failure(
                  core.ValidationFailure(message: 'Licença expirada'),
                );
              }
              if (license.isNotYetValid) {
                LoggerService.warning(
                  'Licença encontrada mas ainda nao em vigor (notBefore '
                  '${license.notBefore?.toIso8601String()})',
                );
                return const rd.Failure(
                  core.ValidationFailure(
                    message: 'Licença ainda não está em vigor',
                  ),
                );
              }
              if (revoked) {
                LoggerService.warning('Licença encontrada mas revogada');
                return const rd.Failure(
                  core.ValidationFailure(message: 'Licença revogada'),
                );
              }
              return rd.Success(license);
            },
            rd.Failure.new,
          );
        },
        rd.Failure.new,
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao obter licença atual', e, stackTrace);
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao obter licença atual: $e',
          originalError: e,
        ),
      );
    }
  }

  /// Lê a licença persistida **sem aplicar expiração/revogação**. UI usa
  /// este método para mostrar o status real ("Licença expirada em X")
  /// em vez de cair para "Sem licença" quando o `getCurrentLicense` já
  /// rejeitou. Veja documentação em [ILicenseValidationService].
  @override
  Future<rd.Result<License>> getStoredLicense() async {
    try {
      final deviceKeyResult = await _deviceKeyService.getDeviceKey();
      return await deviceKeyResult.fold(
        (deviceKey) async {
          return _licenseRepository.getByDeviceKey(deviceKey);
        },
        rd.Failure.new,
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao obter licença armazenada',
        e,
        stackTrace,
      );
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao obter licença armazenada: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<bool>> isFeatureAllowed(String feature) async {
    try {
      final licenseResult = await getCurrentLicense();
      return licenseResult.fold(
        (license) {
          final hasFeature = license.hasFeature(feature);
          return rd.Success(hasFeature);
        },
        (failure) {
          // Distingue causas para diagnóstico: feature negada porque a
          // licença está expirada/revogada/ausente vs erro técnico
          // (DB indisponível). Antes ambos viravam `Success(false)` e
          // o usuário não tinha como saber a diferença na UI.
          LoggerService.debug(
            'isFeatureAllowed("$feature") = false: '
            '${failure is core.Failure ? failure.message : failure}',
          );
          return const rd.Success(false);
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao verificar permissão de recurso: $feature',
        e,
        stackTrace,
      );
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao verificar permissão: $e',
          originalError: e,
        ),
      );
    }
  }
}
