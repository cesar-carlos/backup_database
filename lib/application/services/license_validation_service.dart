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
          // L8 fix: paraleliza a busca da licença e a checagem de
          // revogação. Antes eram sequenciais; cada uma pode envolver
          // I/O (DB local + leitura/parse da revocation list).
          final results = await Future.wait<Object>([
            _licenseRepository.getByDeviceKey(deviceKey),
            _checkRevokedSafely(deviceKey),
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
      LoggerService.error(
        'Erro ao obter licença atual',
        e,
        stackTrace,
      );
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao obter licença atual: $e',
          originalError: e,
        ),
      );
    }
  }

  /// Encapsula a chamada ao revocation checker tornando o fail-open
  /// observável. Antes, `_revocationChecker?.isRevoked(...) ?? false`
  /// silenciosamente assumia "não revogada" quando o checker era null
  /// ou lançava — atacante podia desligar o checker (ex.: corromper a
  /// fonte de revogação) sem rastro nos logs.
  Future<bool> _checkRevokedSafely(String deviceKey) async {
    final checker = _revocationChecker;
    if (checker == null) {
      LoggerService.warning(
        'IRevocationChecker não configurado — assumindo licença não '
        'revogada (fail-open). Configure '
        'BACKUP_DATABASE_LICENSE_REVOCATION_LIST(_PATH) em produção.',
      );
      return false;
    }
    try {
      return await checker.isRevoked(deviceKey);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Falha ao consultar revocation checker — assumindo licença não '
        'revogada (fail-open). Investigue a causa.',
        e,
        stackTrace,
      );
      return false;
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

  @override
  Future<rd.Result<bool>> validateLicense(
    String licenseKey,
    String deviceKey,
  ) async {
    try {
      final licenseResult = await _licenseRepository.getByDeviceKey(deviceKey);
      return await licenseResult.fold(
        (license) async {
          if (license.licenseKey != licenseKey) {
            LoggerService.warning('Chave de licença não corresponde');
            return const rd.Success(false);
          }

          if (license.isExpired) {
            LoggerService.warning('Licença expirada');
            return const rd.Success(false);
          }

          final revoked = await _checkRevokedSafely(deviceKey);
          if (revoked) {
            LoggerService.warning('Licença revogada');
            return const rd.Success(false);
          }

          return const rd.Success(true);
        },
        (failure) {
          return const rd.Success(false);
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao validar licença',
        e,
        stackTrace,
      );
      return rd.Failure(
        core.ServerFailure(
          message: 'Erro ao validar licença: $e',
          originalError: e,
        ),
      );
    }
  }
}
