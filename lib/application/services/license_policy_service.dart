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
  Future<rd.Result<void>> validateScheduleCapabilities(
    Schedule schedule,
  ) async {
    // Monta a lista de checagens necessárias (apenas as features que se
    // aplicam ao schedule). Em seguida, executa TODAS em paralelo via
    // `Future.wait` — antes eram seriais (até 6 awaits), o que doía
    // mais quando a licença não estava cacheada.
    final differentialTypes = {
      BackupType.differential,
      BackupType.convertedDifferential,
    };
    final logTypes = {
      BackupType.log,
      BackupType.convertedLog,
    };

    final checks = <_FeatureCheck>[
      if (differentialTypes.contains(schedule.backupType))
        const _FeatureCheck(
          feature: LicenseFeatures.differentialBackup,
          message:
              'Backup diferencial requer licença com permissão '
              'differential_backup',
        ),
      if (logTypes.contains(schedule.backupType))
        const _FeatureCheck(
          feature: LicenseFeatures.logBackup,
          message: 'Backup de log requer licença com permissão log_backup',
        ),
      if (schedule.scheduleType == 'interval')
        const _FeatureCheck(
          feature: LicenseFeatures.intervalSchedule,
          message:
              'Agendamento por intervalo requer licença com permissão '
              'interval_schedule',
        ),
      if (schedule.enableChecksum)
        const _FeatureCheck(
          feature: LicenseFeatures.checksum,
          message: 'Checksum requer licença com permissão checksum',
        ),
      if (schedule.verifyAfterBackup)
        const _FeatureCheck(
          feature: LicenseFeatures.verifyIntegrity,
          message:
              'Verificação de integridade requer licença com permissão '
              'verify_integrity',
        ),
      if (schedule.postBackupScript?.trim().isNotEmpty ?? false)
        const _FeatureCheck(
          feature: LicenseFeatures.postBackupScript,
          message:
              'Script pós-backup requer licença com permissão '
              'post_backup_script',
        ),
    ];

    if (checks.isEmpty) return const rd.Success(unit);

    final results = await Future.wait(
      checks.map((c) async => (check: c, allowed: await _isFeatureAllowed(c.feature))),
    );

    for (final r in results) {
      if (!r.allowed) {
        _recordLicenseDenied();
        return rd.Failure(
          ValidationFailure(
            message: r.check.message,
            code: FailureCodes.licenseDenied,
          ),
        );
      }
    }

    return const rd.Success(unit);
  }

  /// Mapa estático de destino → (feature, mensagem). Antes era uma cadeia
  /// `switch` com 3 cases quase idênticos, cada um inflando ~10 linhas
  /// com o mesmo pattern. Centralizar reduz risco de divergência (e.g.,
  /// adicionar um destino novo só requer uma entrada aqui).
  static const Map<DestinationType, _DestinationFeatureCheck>
  _destinationFeatureChecks = {
    DestinationType.googleDrive: _DestinationFeatureCheck(
      feature: LicenseFeatures.googleDrive,
      message: 'Google Drive requer licença com permissão google_drive',
    ),
    DestinationType.dropbox: _DestinationFeatureCheck(
      feature: LicenseFeatures.dropbox,
      message: 'Dropbox requer licença com permissão dropbox',
    ),
    DestinationType.nextcloud: _DestinationFeatureCheck(
      feature: LicenseFeatures.nextcloud,
      message: 'Nextcloud requer licença com permissão nextcloud',
    ),
    // local e ftp não requerem feature de licença — retornam Success.
  };

  @override
  Future<rd.Result<void>> validateDestinationCapabilities(
    BackupDestination destination,
  ) async {
    final check = _destinationFeatureChecks[destination.type];
    if (check == null) {
      // Tipos sem feature requirement (local, ftp): autorizado.
      return const rd.Success(unit);
    }

    final allowed = await _isFeatureAllowed(check.feature);
    if (allowed) return const rd.Success(unit);

    _recordLicenseDenied();
    return rd.Failure(
      ValidationFailure(
        message: check.message,
        code: FailureCodes.licenseDenied,
      ),
    );
  }

  @override
  Future<rd.Result<void>> validateExecutionCapabilities(
    Schedule schedule,
    List<BackupDestination> destinations,
  ) async {
    // Schedule e destinations são validados independentemente; rodam em
    // paralelo para minimizar latência total. Antes eram seriais (até
    // N+1 awaits encadeados, onde N = destinations).
    final allChecks = await Future.wait([
      validateScheduleCapabilities(schedule),
      ...destinations.map(validateDestinationCapabilities),
    ]);

    for (final result in allChecks) {
      if (result.isError()) return result;
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

/// Par feature ↔ mensagem usado por [LicensePolicyService] para
/// declarar checagens em batch antes de executar todas em paralelo.
class _FeatureCheck {
  const _FeatureCheck({required this.feature, required this.message});
  final String feature;
  final String message;
}

/// Variante para checagens por tipo de destino (lookup em mapa estático,
/// 1 feature por destino).
class _DestinationFeatureCheck {
  const _DestinationFeatureCheck({
    required this.feature,
    required this.message,
  });
  final String feature;
  final String message;
}
