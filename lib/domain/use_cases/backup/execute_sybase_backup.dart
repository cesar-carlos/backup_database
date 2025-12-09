import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../entities/sybase_config.dart';
import '../../services/backup_execution_result.dart';
import '../../services/i_sybase_backup_service.dart';

class ExecuteSybaseBackup {
  final ISybaseBackupService _backupService;

  ExecuteSybaseBackup(this._backupService);

  Future<rd.Result<BackupExecutionResult>> call({
    required SybaseConfig config,
    required String outputDirectory,
    String? customFileName,
    String? dbbackupPath,
  }) async {
    // Validações
    if (config.serverName.isEmpty) {
      return const rd.Failure(ValidationFailure(
        message: 'Nome do servidor não pode ser vazio',
      ));
    }
    if (config.databaseFile.isEmpty) {
      return const rd.Failure(ValidationFailure(
        message: 'Arquivo do banco não pode ser vazio',
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
      customFileName: customFileName,
      dbbackupPath: dbbackupPath,
    );
  }
}

