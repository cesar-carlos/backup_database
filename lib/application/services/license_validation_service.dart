import 'package:result_dart/result_dart.dart' as rd;

import '../../core/errors/failure.dart' as core;
import '../../core/utils/logger_service.dart';
import '../../domain/entities/license.dart';
import '../../domain/repositories/i_license_repository.dart';
import '../../domain/services/i_device_key_service.dart';
import '../../domain/services/i_license_validation_service.dart';

class LicenseValidationService implements ILicenseValidationService {
  final ILicenseRepository _licenseRepository;
  final IDeviceKeyService _deviceKeyService;

  LicenseValidationService({
    required ILicenseRepository licenseRepository,
    required IDeviceKeyService deviceKeyService,
  })  : _licenseRepository = licenseRepository,
        _deviceKeyService = deviceKeyService;

  @override
  Future<rd.Result<License>> getCurrentLicense() async {
    try {
      final deviceKeyResult = await _deviceKeyService.getDeviceKey();
      return deviceKeyResult.fold(
        (deviceKey) async {
          final licenseResult = await _licenseRepository.getByDeviceKey(deviceKey);
          return licenseResult.fold(
            (license) {
              if (license.isExpired) {
                LoggerService.warning('Licença encontrada mas expirada');
                return rd.Failure(
                  core.ValidationFailure(message: 'Licença expirada'),
                );
              }
              return rd.Success(license);
            },
            (failure) => rd.Failure(failure),
          );
        },
        (failure) => rd.Failure(failure),
      );
    } catch (e, stackTrace) {
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
          // Se não há licença ou está expirada, retorna false
          return const rd.Success(false);
        },
      );
    } catch (e, stackTrace) {
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
      return licenseResult.fold(
        (license) {
          if (license.licenseKey != licenseKey) {
            LoggerService.warning('Chave de licença não corresponde');
            return const rd.Success(false);
          }

          if (license.isExpired) {
            LoggerService.warning('Licença expirada');
            return const rd.Success(false);
          }

          return const rd.Success(true);
        },
        (failure) {
          // Se não encontrou licença, retorna false
          return const rd.Success(false);
        },
      );
    } catch (e, stackTrace) {
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

