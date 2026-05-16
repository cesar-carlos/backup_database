import 'package:backup_database/application/services/strategies/i_database_backup_strategy.dart';
import 'package:backup_database/core/errors/failure.dart' hide Failure;
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:result_dart/result_dart.dart';

class FirebirdBackupStrategyStub implements IDatabaseBackupStrategy {
  const FirebirdBackupStrategyStub();

  static const String _message =
      'Backup Firebird ainda nao esta implementado nesta versao.';

  @override
  DatabaseType get databaseType => DatabaseType.firebird;

  @override
  Future<Result<BackupExecutionResult>> execute({
    required Schedule schedule,
    required Object databaseConfig,
    required String outputDirectory,
    required BackupType backupType,
    required String cancelTag,
  }) async {
    return const Failure(ValidationFailure(message: _message));
  }

  @override
  Future<Result<int>> getDatabaseSizeBytes({
    required Object databaseConfig,
    Duration? timeout,
  }) async {
    return const Failure(ValidationFailure(message: _message));
  }
}
