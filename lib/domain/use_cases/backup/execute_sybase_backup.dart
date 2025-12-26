import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../entities/backup_type.dart';
import '../../entities/sybase_config.dart';
import '../../services/backup_execution_result.dart';
import '../../services/i_sybase_backup_service.dart';

class ExecuteSybaseBackup {
  final ISybaseBackupService _backupService;

  ExecuteSybaseBackup(this._backupService);

  Future<rd.Result<BackupExecutionResult>> call({
    required SybaseConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    String? dbbackupPath,
    bool truncateLog = true,
    bool verifyAfterBackup = false,
  }) async {
    // Validações
    if (config.serverName.trim().isEmpty) {
      return const rd.Failure(ValidationFailure(
        message: 'Nome do servidor não pode ser vazio',
      ));
    }
    if (config.databaseName.trim().isEmpty) {
      return const rd.Failure(ValidationFailure(
        message: 'Nome do banco (DBN) não pode ser vazio',
      ));
    }
    if (config.username.trim().isEmpty) {
      return const rd.Failure(ValidationFailure(
        message: 'Usuário não pode ser vazio',
      ));
    }
    if (outputDirectory.isEmpty) {
      return const rd.Failure(ValidationFailure(
        message: 'Diretório de saída não pode ser vazio',
      ));
    }

    return await _backupService.executeBackup(
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

