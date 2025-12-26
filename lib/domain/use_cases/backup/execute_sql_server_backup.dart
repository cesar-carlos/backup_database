import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../entities/backup_type.dart';
import '../../entities/sql_server_config.dart';
import '../../services/backup_execution_result.dart';
import '../../services/i_sql_server_backup_service.dart';

class ExecuteSqlServerBackup {
  final ISqlServerBackupService _backupService;

  ExecuteSqlServerBackup(this._backupService);

  Future<rd.Result<BackupExecutionResult>> call({
    required SqlServerConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    bool truncateLog = true,
    bool enableChecksum = false,
    bool verifyAfterBackup = false,
  }) async {
    // Validações
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

    return await _backupService.executeBackup(
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
