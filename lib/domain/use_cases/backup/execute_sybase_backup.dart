import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/string_field_validator.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Executa um backup Sybase de forma direta (caminho alternativo ao
/// `BackupOrchestratorService` + strategy pipeline). Útil para fluxos
/// programáticos como CLI/IPC sem schedule.
///
/// Importante: o pipeline da strategy (que vive na camada Application)
/// é a fonte de verdade das regras de validação. Como este use case
/// pula a strategy, precisa replicar as restrições mais críticas aqui
/// — em particular a rejeição de tipos não-nativos do Sybase. Sem isso
/// o service mapearia silenciosamente `differential → log` e produziria
/// um backup diferente do solicitado.
class ExecuteSybaseBackup {
  ExecuteSybaseBackup(this._backupService);
  final ISybaseBackupService _backupService;

  Future<rd.Result<BackupExecutionResult>> call({
    required SybaseConfig config,
    required String outputDirectory,
    String? scheduleId,
    BackupType backupType = BackupType.full,
    String? customFileName,
    String? dbbackupPath,
    bool truncateLog = true,
    bool verifyAfterBackup = false,
    VerifyPolicy verifyPolicy = VerifyPolicy.bestEffort,
    SybaseBackupOptions? sybaseBackupOptions,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    String? cancelTag,
  }) async {
    final validation = StringFieldValidator.requireAllNonBlank({
      'Nome do servidor': config.serverName,
      'Nome do banco (DBN)': config.databaseNameValue,
      'Usuário': config.username,
      'Diretório de saída': outputDirectory,
    });
    if (validation != null) return rd.Failure(validation);

    // Sybase SQL Anywhere não suporta backup differential nativo nem os
    // tipos "convertidos" do legado (Sybase ASE), apenas FULL e
    // TRANSACTION LOG. Antes desta checagem, `backupType=differential`
    // era mapeado silenciosamente para `log` dentro do service — gerando
    // um backup diferente do que o caller pediu. Mesma decisão da
    // `SybaseRejectDifferentialRule` no pipeline.
    if (backupType == BackupType.differential ||
        backupType == BackupType.convertedDifferential ||
        backupType == BackupType.convertedFullSingle ||
        backupType == BackupType.convertedLog) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Sybase SQL Anywhere não suporta backup differential nativo '
              'nem tipos convertidos. Use Full ou Log de Transações.',
        ),
      );
    }

    return _backupService.executeBackup(
      config: config,
      context: BackupExecutionContext(
        outputDirectory: outputDirectory,
        scheduleId: scheduleId ?? config.id,
        backupType: backupType,
        customFileName: customFileName,
        dbbackupPath: dbbackupPath,
        truncateLog: truncateLog,
        verifyAfterBackup: verifyAfterBackup,
        verifyPolicy: verifyPolicy,
        sybaseBackupOptions: sybaseBackupOptions,
        backupTimeout: backupTimeout,
        verifyTimeout: verifyTimeout,
        cancelTag: cancelTag,
      ),
    );
  }
}
