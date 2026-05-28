import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/application/services/i_license_cache_invalidator.dart';
import 'package:backup_database/application/services/license_generation_service.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:flutter/foundation.dart';

class LicenseProvider extends ChangeNotifier with AsyncStateMixin {
  LicenseProvider({
    required ILicenseValidationService validationService,
    required LicenseGenerationService generationService,
    required ILicenseRepository licenseRepository,
    required IDeviceKeyService deviceKeyService,
    ILicenseCacheInvalidator? cacheInvalidator,
  }) : _validationService = validationService,
       _generationService = generationService,
       _licenseRepository = licenseRepository,
       _deviceKeyService = deviceKeyService,
       _cacheInvalidator = cacheInvalidator {
    unawaited(loadDeviceKey());
    unawaited(loadLicense());
  }
  final ILicenseValidationService _validationService;
  final LicenseGenerationService _generationService;
  final ILicenseRepository _licenseRepository;
  final IDeviceKeyService _deviceKeyService;
  final ILicenseCacheInvalidator? _cacheInvalidator;

  License? _currentLicense;
  String? _deviceKey;

  License? get currentLicense => _currentLicense;
  String? get deviceKey => _deviceKey;
  bool get canGenerateLicenses => _generationService.canGenerateLocally;
  bool get hasValidLicense =>
      _currentLicense != null && _currentLicense!.isValid;

  Future<void> loadDeviceKey() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao obter chave do dispositivo',
      action: () async {
        final deviceKeyResult = await _deviceKeyService.getDeviceKey();
        deviceKeyResult.fold(
          (key) => _deviceKey = key,
          (failure) => throw failure,
        );
      },
    );
  }

  Future<void> loadLicense() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao carregar licença',
      action: () async {
        // Usa `getStoredLicense` (não `getCurrentLicense`) para que a UI
        // consiga renderizar status "Licença expirada"/"Ainda não em
        // vigor". Antes a UI só conseguia mostrar "Sem licença" para
        // qualquer falha, porque `getCurrentLicense` filtra
        // expirada/revogada por contrato.
        //
        // Validações de feature continuam passando por
        // `LicensePolicyService` → `getCurrentLicense` no caminho de
        // execução de backup; o getter `hasValidLicense` aqui aplica
        // `License.isValid` (expira/notBefore), sem revogação — para
        // gating remoto a UI deve consultar policy quando crítico.
        final licenseResult = await _validationService.getStoredLicense();
        licenseResult.fold(
          (license) => _currentLicense = license,
          (failure) {
            _currentLicense = null;
            // NotFound não é erro de negócio: usuário ainda não cadastrou
            // licença. Sinalizamos limpando estado, sem propagar a falha.
            if (failure is! core.NotFoundFailure) {
              throw failure;
            }
          },
        );
      },
    );
  }

  Future<bool> validateAndSaveLicense(String licenseKey) async {
    if (_deviceKey == null) {
      setErrorManual('Chave do dispositivo não disponível');
      return false;
    }

    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao validar licença',
      action: () async {
        final createResult = await _generationService.createLicenseFromKey(
          licenseKey: licenseKey,
          deviceKey: _deviceKey!,
        );

        final license = createResult.fold(
          (license) => license,
          (failure) => throw failure,
        );

        final saveResult = await _licenseRepository.upsertByDeviceKey(license);
        return saveResult.fold(
          (saved) {
            _cacheInvalidator?.invalidateLicenseCache();
            _currentLicense = saved;
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> isFeatureAllowed(String feature) async {
    try {
      final result = await _validationService.isFeatureAllowed(feature);
      return result.fold(
        (allowed) => allowed,
        (failure) {
          // Fail-closed mas observável: antes engolíamos a falha sem
          // log, impedindo diagnóstico de "por que feature X aparece
          // negada?".
          LoggerService.debug(
            'LicenseProvider.isFeatureAllowed("$feature") = false: '
            '${failure is core.Failure ? failure.message : failure}',
          );
          return false;
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'LicenseProvider.isFeatureAllowed("$feature") falhou — '
        'fail-closed (assumindo negada).',
        e,
        stackTrace,
      );
      return false;
    }
  }

  void setDeviceKey(String deviceKey) {
    _deviceKey = deviceKey;
    notifyListeners();
  }

  Future<String?> generateLicense({
    required String deviceKey,
    required List<String> allowedFeatures,
    DateTime? expiresAt,
    DateTime? notBefore,
  }) {
    return runAsync<String>(
      genericErrorMessage: 'Erro ao gerar licença',
      action: () async {
        final generateResult = await _generationService.generateLicenseKey(
          deviceKey: deviceKey,
          expiresAt: expiresAt,
          notBefore: notBefore,
          allowedFeatures: allowedFeatures,
        );
        return generateResult.fold(
          (licenseKey) => licenseKey,
          (failure) => throw failure,
        );
      },
    );
  }
}
