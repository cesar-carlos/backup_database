import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/application/services/i_license_cache_invalidator.dart';
import 'package:backup_database/application/services/license_decoder.dart';
import 'package:backup_database/application/services/license_generation_service.dart';
import 'package:backup_database/application/services/license_trial_policy.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/errors/failure.dart' as core;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:flutter/foundation.dart';

class LicenseProvider extends ChangeNotifier with AsyncStateMixin {
  LicenseProvider({
    required this._validationService,
    required this._generationService,
    required this._licenseRepository,
    required this._deviceKeyService,
    this._cacheInvalidator,
    this._decoder,
    LicenseTrialPolicy? trialPolicy,
  }) : _trialPolicy = trialPolicy ?? LicenseTrialPolicy() {
    unawaited(loadDeviceKey());
    unawaited(loadLicense());
  }
  final ILicenseValidationService _validationService;
  final LicenseGenerationService _generationService;
  final ILicenseRepository _licenseRepository;
  final IDeviceKeyService _deviceKeyService;
  final ILicenseCacheInvalidator? _cacheInvalidator;
  final LicenseDecoder? _decoder;
  final LicenseTrialPolicy _trialPolicy;

  License? _storedLicense;
  License? _effectiveLicense;
  String? _deviceKey;
  bool _isLicenseLoaded = false;
  bool _isDeviceRevoked = false;

  License? get storedLicense => _storedLicense;
  License? get effectiveLicense => _effectiveLicense;

  /// Licença efetiva (trial sintético ou premium válida).
  License? get currentLicense => _effectiveLicense;

  String? get deviceKey => _deviceKey;
  bool get canGenerateLicenses => _generationService.canGenerateLocally;
  bool get isLicenseLoaded => _isLicenseLoaded;
  bool get isDeviceRevoked => _isDeviceRevoked;
  bool get isDecoderDegraded => _decoder != null && !_decoder.isAvailable;

  bool get hasValidLicense =>
      _effectiveLicense != null && _effectiveLicense!.isValid;

  bool get isTrialActive => _effectiveLicense?.isTrial ?? false;

  bool get showTrialReminder => isTrialActive && _trialPolicy.isReminderWindow;

  bool get isTrialEndedWithoutPremium =>
      _isLicenseLoaded &&
      !_isDeviceRevoked &&
      _effectiveLicense == null &&
      (_storedLicense == null || !_storedLicense!.isValid);

  bool isFeatureUnlocked(String feature) {
    final license = _effectiveLicense;
    if (license == null || !license.isValid) return false;
    return license.hasFeature(feature);
  }

  bool scheduleUsesLockedPremium(
    Schedule schedule, [
    List<BackupDestination> destinations = const [],
  ]) {
    if (!_isLicenseLoaded) return false;

    final differentialTypes = {
      BackupType.differential,
      BackupType.convertedDifferential,
    };
    final logTypes = {BackupType.log, BackupType.convertedLog};

    if (differentialTypes.contains(schedule.backupType) &&
        !isFeatureUnlocked(LicenseFeatures.differentialBackup)) {
      return true;
    }
    if (logTypes.contains(schedule.backupType) &&
        !isFeatureUnlocked(LicenseFeatures.logBackup)) {
      return true;
    }
    if (schedule.scheduleType == 'interval' &&
        !isFeatureUnlocked(LicenseFeatures.intervalSchedule)) {
      return true;
    }
    if (schedule.enableChecksum &&
        !isFeatureUnlocked(LicenseFeatures.checksum)) {
      return true;
    }
    if (schedule.verifyAfterBackup &&
        !isFeatureUnlocked(LicenseFeatures.verifyIntegrity)) {
      return true;
    }
    if ((schedule.postBackupScript?.trim().isNotEmpty ?? false) &&
        !isFeatureUnlocked(LicenseFeatures.postBackupScript)) {
      return true;
    }

    final destinationById = {
      for (final destination in destinations) destination.id: destination,
    };
    for (final id in schedule.destinationIds) {
      final destination = destinationById[id];
      if (destination != null && destinationUsesLockedPremium(destination)) {
        return true;
      }
    }
    return false;
  }

  bool destinationUsesLockedPremium(BackupDestination destination) {
    if (!_isLicenseLoaded) return false;
    return switch (destination.type) {
      DestinationType.googleDrive => !isFeatureUnlocked(
        LicenseFeatures.googleDrive,
      ),
      DestinationType.dropbox => !isFeatureUnlocked(LicenseFeatures.dropbox),
      DestinationType.nextcloud => !isFeatureUnlocked(
        LicenseFeatures.nextcloud,
      ),
      DestinationType.local || DestinationType.ftp => false,
    };
  }

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
        try {
          final results = await Future.wait([
            _validationService.getStoredLicense(),
            _validationService.getCurrentLicense(),
          ]);
          final storedResult = results[0];
          final currentResult = results[1];

          storedResult.fold(
            (license) => _storedLicense = license,
            (failure) {
              _storedLicense = null;
              if (failure is! core.NotFoundFailure) {
                throw failure;
              }
            },
          );

          currentResult.fold(
            (license) {
              _effectiveLicense = license;
              _isDeviceRevoked = false;
            },
            (failure) {
              _effectiveLicense = null;
              final message = failure is core.Failure
                  ? failure.message
                  : failure.toString();
              _isDeviceRevoked = message.contains('revogada');
              if (failure is core.ServerFailure) {
                throw failure;
              }
            },
          );
        } finally {
          _isLicenseLoaded = true;
        }
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
        final saved = saveResult.getOrNull();
        if (saved == null) {
          throw saveResult.exceptionOrNull()!;
        }

        _cacheInvalidator?.invalidateLicenseCache();
        _storedLicense = saved;
        final currentResult = await _validationService.getCurrentLicense();
        currentResult.fold(
          (current) {
            _effectiveLicense = current;
            _isDeviceRevoked = false;
          },
          (failure) {
            _effectiveLicense = null;
            final message = failure is core.Failure
                ? failure.message
                : failure.toString();
            _isDeviceRevoked = message.contains('revogada');
          },
        );
        _isLicenseLoaded = true;
        return true;
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
