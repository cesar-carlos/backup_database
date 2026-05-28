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

  /// Cache de feature lookup escopo por `runId` em vez de variável de
  /// instância única. Antes era `String? _runContext` +
  /// `Map<String, bool> _runFeatureCache` no singleton — duas execuções
  /// concorrentes (UI local + comando socket remoto, ou múltiplos
  /// schedules em paralelo) clobberavam o cache uma da outra e
  /// `clearRunContext()` de uma corrida zerava o cache da outra.
  ///
  /// Agora cada runId carrega seu próprio mapa; runs concorrentes ficam
  /// isolados e `clearRunContext` só remove o slot do run que terminou.
  final Map<String, Map<String, bool>> _runFeatureCacheByRunId = {};

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
      checks.map(
        (c) async => (check: c, allowed: await _isFeatureAllowed(c.feature)),
      ),
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

  /// runId "atual" — usado pelas APIs de validação para chavear o cache.
  /// Em fluxo de execução normal, `SchedulerService` chama
  /// `setRunContext('A')` antes e `clearRunContext()` no fim. Para runs
  /// concorrentes, a memoização agora é por runId (não global) — veja
  /// `_runFeatureCacheByRunId`.
  String? _runContext;

  @override
  void setRunContext(String? runId) {
    _runContext = runId;
    if (runId != null) {
      // `putIfAbsent` em vez de `=` para que reativar o mesmo runId
      // (ex.: depois de um nested clear/set legítimo) **preserve** o
      // cache. Antes, `setRunContext` sempre zerava o cache do runId,
      // o que penalizava cenários reentrantes legítimos.
      _runFeatureCacheByRunId.putIfAbsent(runId, () => <String, bool>{});
    }
  }

  @override
  void clearRunContext() {
    final current = _runContext;
    _runContext = null;
    if (current != null) {
      _runFeatureCacheByRunId.remove(current);
    }
  }

  Future<bool> _isFeatureAllowed(String feature) async {
    final runId = _runContext;
    if (runId != null) {
      final cache = _runFeatureCacheByRunId[runId];
      final cached = cache?[feature];
      if (cached != null) {
        return cached;
      }
    }
    final result = await _licenseValidationService.isFeatureAllowed(feature);
    final allowed = result.getOrElse((_) => false);
    if (runId != null) {
      // Cache pode ter sido removido entre o setRunContext e o lookup
      // (clearRunContext concorrente) — `putIfAbsent` evita recriar e
      // perder dados que possam ter chegado por outra fonte.
      final cache = _runFeatureCacheByRunId.putIfAbsent(
        runId,
        () => <String, bool>{},
      );
      cache[feature] = allowed;
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
