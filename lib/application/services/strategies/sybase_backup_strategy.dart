import 'package:backup_database/application/services/strategies/i_database_backup_strategy.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Estratégia de backup específica para Sybase SQL Anywhere.
///
/// Concentra todas as regras Sybase-only do orchestrator: preflight de
/// log, rejeição de differential nativo, bloqueio de TRUNCATE em
/// ambientes de replicação, e enriquecimento de `metrics.sybaseOptions`
/// com metadados da cadeia (`baseFullId`, `chainStartAt`, `logSequence`).
class SybaseBackupStrategy implements IDatabaseBackupStrategy {
  SybaseBackupStrategy({
    required ISybaseBackupService service,
    required ValidateSybaseLogBackupPreflight validatePreflight,
  }) : _service = service,
       _validatePreflight = validatePreflight;

  final ISybaseBackupService _service;
  final ValidateSybaseLogBackupPreflight _validatePreflight;

  @override
  DatabaseType get databaseType => DatabaseType.sybase;

  @override
  Future<rd.Result<BackupExecutionResult>> execute({
    required Schedule schedule,
    required Object databaseConfig,
    required String outputDirectory,
    required BackupType backupType,
    required String cancelTag,
  }) async {
    final config = databaseConfig as SybaseConfig;

    // 1. Differential nativo: rejeita explicitamente (antes era convertido
    //    silenciosamente em LOG, gerando histórico inconsistente).
    if (backupType == BackupType.differential) {
      const message =
          'Sybase SQL Anywhere não suporta backup differential nativo. '
          'Configure o agendamento como Full ou Log de Transações.';
      LoggerService.error(message);
      return const rd.Failure(ValidationFailure(message: message));
    }

    // 2. Preflight de log: valida cadeia FULL → LOG e captura metadata.
    SybaseLogBackupPreflightResult? preflight;
    if (backupType == BackupType.log) {
      final preflightResult = await _validatePreflight(schedule);
      if (preflightResult.isError()) {
        return rd.Failure(preflightResult.exceptionOrNull()!);
      }
      preflight = preflightResult.getOrNull();
      if (preflight == null) {
        return const rd.Failure(
          ValidationFailure(message: 'Preflight retornou resultado nulo'),
        );
      }
      if (!preflight.canProceed) {
        LoggerService.error('Preflight Sybase log: ${preflight.error}');
        return rd.Failure(
          ValidationFailure(message: preflight.error ?? 'Preflight falhou'),
        );
      }
      if (preflight.warning != null) {
        LoggerService.warning('Preflight Sybase log: ${preflight.warning}');
      }
    }

    // 3. Opções específicas do schedule.
    final SybaseBackupOptions? sybaseOptions;
    if (schedule is SybaseBackupSchedule) {
      sybaseOptions = schedule.sybaseBackupOptions;
    } else {
      sybaseOptions = null;
      LoggerService.warning(
        'Schedule "${schedule.name}" do tipo Sybase foi carregado sem '
        'SybaseBackupOptions. Backup usará defaults seguros.',
      );
    }

    // 4. TRUNCATE proibido em ambiente de replicação.
    if (config.isReplicationEnvironment &&
        backupType == BackupType.log &&
        (sybaseOptions ?? SybaseBackupOptions.safeDefaults)
                .effectiveLogMode(truncateLog: schedule.truncateLog) ==
            SybaseLogBackupMode.truncate) {
      const message =
          'Backup de log com modo Truncar (TRUNCATE) não é permitido em '
          'ambientes de replicação (SQL Remote, MobiLink). '
          'Use modo Renomear ou Apenas na configuração do agendamento.';
      LoggerService.error(message);
      return const rd.Failure(ValidationFailure(message: message));
    }

    // 5. Executa o backup propriamente dito.
    final backupResult = await _service.executeBackup(
      config: config,
      outputDirectory: outputDirectory,
      backupType: backupType,
      truncateLog: schedule.truncateLog,
      verifyAfterBackup: schedule.verifyAfterBackup,
      verifyPolicy: schedule.verifyPolicy,
      backupTimeout: schedule.backupTimeout,
      verifyTimeout: schedule.verifyTimeout,
      sybaseBackupOptions: sybaseOptions,
      cancelTag: cancelTag,
    );

    if (backupResult.isError() || preflight == null) {
      return backupResult;
    }

    // 6. Enriquece metrics.sybaseOptions com info da cadeia.
    final exec = backupResult.getOrNull()!;
    final base = exec.metrics?.sybaseOptions != null
        ? Map<String, dynamic>.from(exec.metrics!.sybaseOptions!)
        : <String, dynamic>{};
    if (preflight.baseFull != null && preflight.nextLogSequence != null) {
      final baseFull = preflight.baseFull!;
      base['baseFullId'] = baseFull.id;
      base['chainStartAt'] = (baseFull.finishedAt ?? baseFull.startedAt)
          .toIso8601String();
      base['logSequence'] = preflight.nextLogSequence;
    }
    final enrichedMetrics = exec.metrics?.copyWith(sybaseOptions: base);
    return rd.Success(
      BackupExecutionResult(
        backupPath: exec.backupPath,
        fileSize: exec.fileSize,
        duration: exec.duration,
        databaseName: exec.databaseName,
        metrics: enrichedMetrics ?? exec.metrics,
        executedBackupType: exec.executedBackupType,
      ),
    );
  }
}
