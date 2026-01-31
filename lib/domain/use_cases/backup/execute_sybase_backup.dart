import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ExecuteSybaseBackup {
  ExecuteSybaseBackup(this._backupService);
  final ISybaseBackupService _backupService;

  Future<rd.Result<BackupExecutionResult>> call({
    required SybaseConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    String? dbbackupPath,
    bool truncateLog = true,
    bool verifyAfterBackup = false,
  }) async {
    if (config.serverName.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Nome do servidor não pode ser vazio',
        ),
      );
    }
    if (config.databaseName.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Nome do banco (DBN) não pode ser vazio',
        ),
      );
    }
    if (config.username.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Usuário não pode ser vazio',
        ),
      );
    }
    if (outputDirectory.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Diretório de saída não pode ser vazio',
        ),
      );
    }

    return _backupService.executeBackup(
      config: config,
      outputDirectory: outputDirectory,
      backupType: backupType,
      customFileName: customFileName,
      dbbackupPath: dbbackupPath,
      truncateLog: truncateLog,
      verifyAfterBackup: verifyAfterBackup,
    );
  }
}
