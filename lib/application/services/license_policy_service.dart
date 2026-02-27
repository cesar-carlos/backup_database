import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class LicensePolicyService implements ILicensePolicyService {
  LicensePolicyService({
    required ILicenseValidationService licenseValidationService,
    IMetricsCollector? metricsCollector,
  }) : _licenseValidationService = licenseValidationService,
       _metricsCollector = metricsCollector;

  final ILicenseValidationService _licenseValidationService;
  final IMetricsCollector? _metricsCollector;

  void _recordLicenseDenied() {
    _metricsCollector?.incrementCounter(
      ObservabilityMetrics.licenseDeniedTotal,
    );
  }

  String? _runContext;
  final Map<String, bool> _runFeatureCache = {};

  @override
  Future<rd.Result<void>> validateScheduleCapabilities(Schedule schedule) async {
    final differentialTypes = [
      BackupType.differential,
      BackupType.convertedDifferential,
    ];
    final logTypes = [
      BackupType.log,
      BackupType.convertedLog,
    ];

    if (differentialTypes.contains(schedule.backupType)) {
      final allowed = await _isFeatureAllowed(LicenseFeatures.differentialBackup);
      if (!allowed) {
        _recordLicenseDenied();
        return const rd.Failure(
          ValidationFailure(
            message:
                'Backup diferencial requer licença com permissão differential_backup',
            code: FailureCodes.licenseDenied,
          ),
        );
      }
    }

    if (logTypes.contains(schedule.backupType)) {
      final allowed = await _isFeatureAllowed(LicenseFeatures.logBackup);
      if (!allowed) {
        _recordLicenseDenied();
        return const rd.Failure(
          ValidationFailure(
            message:
                'Backup de log requer licença com permissão log_backup',
            code: FailureCodes.licenseDenied,
          ),
        );
      }
    }

    if (schedule.scheduleType == 'interval') {
      final allowed = await _isFeatureAllowed(LicenseFeatures.intervalSchedule);
      if (!allowed) {
        _recordLicenseDenied();
        return const rd.Failure(
          ValidationFailure(
            message:
                'Agendamento por intervalo requer licença com permissão interval_schedule',
            code: FailureCodes.licenseDenied,
          ),
        );
      }
    }

    if (schedule.enableChecksum) {
      final allowed = await _isFeatureAllowed(LicenseFeatures.checksum);
      if (!allowed) {
        _recordLicenseDenied();
        return const rd.Failure(
          ValidationFailure(
            message:
                'Checksum requer licença com permissão checksum',
            code: FailureCodes.licenseDenied,
          ),
        );
      }
    }

    if (schedule.verifyAfterBackup) {
      final allowed = await _isFeatureAllowed(LicenseFeatures.verifyIntegrity);
      if (!allowed) {
        _recordLicenseDenied();
        return const rd.Failure(
          ValidationFailure(
            message:
                'Verificação de integridade requer licença com permissão verify_integrity',
            code: FailureCodes.licenseDenied,
          ),
        );
      }
    }

    final hasPostScript = schedule.postBackupScript != null &&
        schedule.postBackupScript!.trim().isNotEmpty;
    if (hasPostScript) {
      final allowed =
          await _isFeatureAllowed(LicenseFeatures.postBackupScript);
      if (!allowed) {
        _recordLicenseDenied();
        return const rd.Failure(
          ValidationFailure(
            message:
                'Script pós-backup requer licença com permissão post_backup_script',
            code: FailureCodes.licenseDenied,
          ),
        );
      }
    }

    return const rd.Success(unit);
  }

  @override
  Future<rd.Result<void>> validateDestinationCapabilities(
    BackupDestination destination,
  ) async {
    switch (destination.type) {
      case DestinationType.googleDrive:
        final allowed = await _isFeatureAllowed(LicenseFeatures.googleDrive);
        if (!allowed) {
          _recordLicenseDenied();
          return const rd.Failure(
            ValidationFailure(
              message:
                  'Google Drive requer licença com permissão google_drive',
              code: FailureCodes.licenseDenied,
            ),
          );
        }
      case DestinationType.dropbox:
        final allowed = await _isFeatureAllowed(LicenseFeatures.dropbox);
        if (!allowed) {
          _recordLicenseDenied();
          return const rd.Failure(
            ValidationFailure(
              message: 'Dropbox requer licença com permissão dropbox',
              code: FailureCodes.licenseDenied,
            ),
          );
        }
      case DestinationType.nextcloud:
        final allowed = await _isFeatureAllowed(LicenseFeatures.nextcloud);
        if (!allowed) {
          _recordLicenseDenied();
          return const rd.Failure(
            ValidationFailure(
              message:
                  'Nextcloud requer licença com permissão nextcloud',
              code: FailureCodes.licenseDenied,
            ),
          );
        }
      case DestinationType.local:
      case DestinationType.ftp:
        break;
    }

    return const rd.Success(unit);
  }

  @override
  Future<rd.Result<void>> validateExecutionCapabilities(
    Schedule schedule,
    List<BackupDestination> destinations,
  ) async {
    final scheduleResult = await validateScheduleCapabilities(schedule);
    if (scheduleResult.isError()) {
      return scheduleResult;
    }

    for (final dest in destinations) {
      final destResult = await validateDestinationCapabilities(dest);
      if (destResult.isError()) {
        return destResult;
      }
    }

    return const rd.Success(unit);
  }

  @override
  void setRunContext(String? runId) {
    _runContext = runId;
    _runFeatureCache.clear();
  }

  @override
  void clearRunContext() {
    _runContext = null;
    _runFeatureCache.clear();
  }

  Future<bool> _isFeatureAllowed(String feature) async {
    if (_runContext != null) {
      final cached = _runFeatureCache[feature];
      if (cached != null) {
        return cached;
      }
    }
    final result = await _licenseValidationService.isFeatureAllowed(feature);
    final allowed = result.getOrElse((_) => false);
    if (_runContext != null) {
      _runFeatureCache[feature] = allowed;
    }
    return allowed;
  }
}
