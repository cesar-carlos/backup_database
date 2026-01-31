import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ExecuteSqlServerBackup {
  ExecuteSqlServerBackup(this._backupService);
  final ISqlServerBackupService _backupService;

  Future<rd.Result<BackupExecutionResult>> call({
    required SqlServerConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    bool truncateLog = true,
    bool enableChecksum = false,
    bool verifyAfterBackup = false,
  }) async {
    if (config.server.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Servidor não pode ser vazio'),
      );
    }
    if (config.database.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Nome do banco não pode ser vazio'),
      );
    }
    if (outputDirectory.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Diretório de saída não pode ser vazio'),
      );
    }

    return _backupService.executeBackup(
      config: config,
      outputDirectory: outputDirectory,
      backupType: backupType,
      customFileName: customFileName,
      truncateLog: truncateLog,
      enableChecksum: enableChecksum,
      verifyAfterBackup: verifyAfterBackup,
    );
  }
}
