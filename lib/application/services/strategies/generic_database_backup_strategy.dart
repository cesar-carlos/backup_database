import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/backup_result_enricher.dart';
import 'package:backup_database/application/services/strategies/backup_validation_rule.dart';
import 'package:backup_database/application/services/strategies/i_database_backup_strategy.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_database_backup_port.dart';
import 'package:result_dart/result_dart.dart' as rd;

typedef BuildBackupExecutionContext<T extends DatabaseConnectionConfig> =
    BackupExecutionContext Function({
      required Schedule schedule,
      required T config,
      required String outputDirectory,
      required BackupType backupType,
      required String cancelTag,
    });

class GenericDatabaseBackupStrategy<T extends DatabaseConnectionConfig>
    implements IDatabaseBackupStrategy {
  GenericDatabaseBackupStrategy({
    required DatabaseType databaseType,
    required IDatabaseBackupPort<T> port,
    required List<BackupValidationRule<T>> rules,
    required List<BackupResultEnricher<T>> enrichers,
    required BuildBackupExecutionContext<T> buildContext,
  }) : _databaseType = databaseType,
       _port = port,
       _rules = rules,
       _enrichers = enrichers,
       _buildContext = buildContext;

  final DatabaseType _databaseType;
  final IDatabaseBackupPort<T> _port;
  final List<BackupValidationRule<T>> _rules;
  final List<BackupResultEnricher<T>> _enrichers;
  final BuildBackupExecutionContext<T> _buildContext;

  @override
  DatabaseType get databaseType => _databaseType;

  @override
  Future<rd.Result<BackupExecutionResult>> execute({
    required Schedule schedule,
    required Object databaseConfig,
    required String outputDirectory,
    required BackupType backupType,
    required String cancelTag,
  }) async {
    final config = databaseConfig as T;
    final pipelineContext = BackupPipelineContext();
    for (final rule in _rules) {
      final step = await rule.validate(
        pipelineContext,
        schedule: schedule,
        config: config,
        backupType: backupType,
      );
      if (step.isError()) {
        return rd.Failure(step.exceptionOrNull()!);
      }
    }
    final execContext = _buildContext(
      schedule: schedule,
      config: config,
      outputDirectory: outputDirectory,
      backupType: backupType,
      cancelTag: cancelTag,
    );
    final backupResult = await _port.executeBackup(
      config: config,
      context: execContext,
    );
    if (backupResult.isError()) {
      return backupResult;
    }
    var merged = backupResult.getOrNull()!;
    for (final enricher in _enrichers) {
      merged = await enricher.enrich(
        pipelineContext,
        schedule: schedule,
        config: config,
        backupType: backupType,
        result: merged,
      );
    }
    return rd.Success(merged);
  }

  @override
  Future<rd.Result<int>> getDatabaseSizeBytes({
    required Object databaseConfig,
    Duration? timeout,
  }) {
    final config = databaseConfig as T;
    return _port.getDatabaseSizeBytes(config: config, timeout: timeout);
  }
}
