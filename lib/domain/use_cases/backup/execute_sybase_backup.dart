import 'package:backup_database/core/utils/string_field_validator.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
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
    VerifyPolicy verifyPolicy = VerifyPolicy.bestEffort,
  }) async {
    final validation = StringFieldValidator.requireAllNonBlank({
      'Nome do servidor': config.serverName,
      'Nome do banco (DBN)': config.databaseNameValue,
      'Usuário': config.username,
      'Diretório de saída': outputDirectory,
    });
    if (validation != null) return rd.Failure(validation);

    return _backupService.executeBackup(
      config: config,
      context: BackupExecutionContext(
        outputDirectory: outputDirectory,
        scheduleId: config.id,
        backupType: backupType,
        customFileName: customFileName,
        dbbackupPath: dbbackupPath,
        truncateLog: truncateLog,
        verifyAfterBackup: verifyAfterBackup,
        verifyPolicy: verifyPolicy,
      ),
    );
  }
}
