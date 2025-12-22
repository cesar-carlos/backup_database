import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';
import '../../core/di/service_locator.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/backup_history.dart';
import '../../domain/entities/backup_log.dart';
import '../../domain/entities/backup_type.dart';
import '../../domain/entities/sql_server_config.dart';
import '../../domain/entities/sybase_config.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/i_sql_server_backup_service.dart';
import '../../domain/services/i_sql_script_execution_service.dart';
import '../../domain/services/i_sybase_backup_service.dart';
import '../../domain/services/i_compression_service.dart';
import '../providers/backup_progress_provider.dart';
import 'notification_service.dart';

class BackupOrchestratorService {
  final ISqlServerConfigRepository _sqlServerConfigRepository;
  final ISybaseConfigRepository _sybaseConfigRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupLogRepository _backupLogRepository;
  final ISqlServerBackupService _sqlServerBackupService;
  final ISybaseBackupService _sybaseBackupService;
  final ICompressionService _compressionService;
  final ISqlScriptExecutionService _sqlScriptExecutionService;
  final NotificationService _notificationService;

  BackupOrchestratorService({
    required ISqlServerConfigRepository sqlServerConfigRepository,
    required ISybaseConfigRepository sybaseConfigRepository,
    required IBackupHistoryRepository backupHistoryRepository,
    required IBackupLogRepository backupLogRepository,
    required ISqlServerBackupService sqlServerBackupService,
    required ISybaseBackupService sybaseBackupService,
    required ICompressionService compressionService,
    required ISqlScriptExecutionService sqlScriptExecutionService,
    required NotificationService notificationService,
  })  : _sqlServerConfigRepository = sqlServerConfigRepository,
        _sybaseConfigRepository = sybaseConfigRepository,
        _backupHistoryRepository = backupHistoryRepository,
        _backupLogRepository = backupLogRepository,
        _sqlServerBackupService = sqlServerBackupService,
        _sybaseBackupService = sybaseBackupService,
        _compressionService = compressionService,
        _sqlScriptExecutionService = sqlScriptExecutionService,
        _notificationService = notificationService;

  Future<rd.Result<BackupHistory>> executeBackup({
    required Schedule schedule,
    required String outputDirectory,
  }) async {
    LoggerService.info('Iniciando backup para schedule: ${schedule.name}');

    // Validar que o caminho de saída não está vazio
    if (outputDirectory.isEmpty) {
      final errorMessage =
          'Caminho de saída do backup está vazio para o agendamento: ${schedule.name}';
      LoggerService.error(errorMessage);
      return rd.Failure(ValidationFailure(message: errorMessage));
    }

    // Obter tipo de backup do schedule
    final backupType = schedule.backupType;

    // Criar subpasta por tipo de backup
    final typeFolderName = backupType.displayName;
    final typeOutputDirectory = p.join(outputDirectory, typeFolderName);
    
    // Validar que o caminho final não está vazio
    if (typeOutputDirectory.isEmpty) {
      final errorMessage =
          'Caminho de saída do backup por tipo está vazio para o agendamento: ${schedule.name}';
      LoggerService.error(errorMessage);
      return rd.Failure(ValidationFailure(message: errorMessage));
    }
    
    final typeOutputDir = Directory(typeOutputDirectory);
    if (!await typeOutputDir.exists()) {
      try {
        await typeOutputDir.create(recursive: true);
      } catch (e) {
        final errorMessage =
            'Erro ao criar pasta de backup por tipo: $typeOutputDirectory';
        LoggerService.error(errorMessage, e);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }
    }

    LoggerService.info(
      'Diretório de backup por tipo: $typeOutputDirectory (Tipo: ${backupType.displayName})',
    );

    // Criar registro de histórico com status "running"
    var history = BackupHistory(
      scheduleId: schedule.id,
      databaseName: schedule.name,
      databaseType: schedule.databaseType.name,
      backupPath: '',
      fileSize: 0,
      backupType: backupType.name,
      status: BackupStatus.running,
      startedAt: DateTime.now(),
    );

    final createResult = await _backupHistoryRepository.create(history);
    if (createResult.isError()) {
      return rd.Failure(createResult.exceptionOrNull()!);
    }
    history = createResult.getOrNull()!;

    await _log(history.id, 'info', 'Backup iniciado');

    try {
      // Executar backup baseado no tipo
      String backupPath;
      int fileSize;

      if (schedule.databaseType == DatabaseType.sqlServer) {
        final configResult = await _sqlServerConfigRepository.getById(
          schedule.databaseConfigId,
        );
        if (configResult.isError()) {
          throw Exception('Configuração SQL Server não encontrada');
        }

        final backupResult = await _sqlServerBackupService.executeBackup(
          config: configResult.getOrNull()!,
          outputDirectory: typeOutputDirectory,
          backupType: backupType,
          truncateLog: schedule.truncateLog,
          enableChecksum: schedule.enableChecksum,
          verifyAfterBackup: schedule.verifyAfterBackup,
        );

        if (backupResult.isError()) {
          final failure = backupResult.exceptionOrNull()! as Failure;
          throw Exception(failure.message);
        }

        backupPath = backupResult.getOrNull()!.backupPath;
        fileSize = backupResult.getOrNull()!.fileSize;
      } else {
        final configResult = await _sybaseConfigRepository.getById(
          schedule.databaseConfigId,
        );
        if (configResult.isError()) {
          final failure = configResult.exceptionOrNull();
          final errorMessage = failure is Failure 
              ? failure.message 
              : 'Configuração Sybase não encontrada';
          LoggerService.error(
            'Falha ao buscar configuração Sybase',
            'Schedule: ${schedule.name}, ConfigId: ${schedule.databaseConfigId}, Erro: $errorMessage',
          );
          throw Exception(errorMessage);
        }

        final backupResult = await _sybaseBackupService.executeBackup(
          config: configResult.getOrNull()!,
          outputDirectory: typeOutputDirectory,
          backupType: backupType,
          truncateLog: schedule.truncateLog,
          verifyAfterBackup: schedule.verifyAfterBackup,
        );

        if (backupResult.isError()) {
          final failure = backupResult.exceptionOrNull()! as Failure;
          throw Exception(failure.message);
        }

        backupPath = backupResult.getOrNull()!.backupPath;
        fileSize = backupResult.getOrNull()!.fileSize;
      }

      await _log(history.id, 'info', 'Backup do banco concluído');

      // Atualizar progresso
      try {
        final progressProvider = getIt<BackupProgressProvider>();
        progressProvider.updateProgress(
          step: BackupStep.executingBackup,
          message: 'Backup do banco concluído',
          progress: 0.5,
        );
      } catch (_) {
        // Ignorar se não estiver disponível
      }

      // Comprimir se configurado
      if (schedule.compressBackup) {
        await _log(history.id, 'info', 'Iniciando compressão');

        // Atualizar progresso
        try {
          final progressProvider = getIt<BackupProgressProvider>();
          progressProvider.updateProgress(
            step: BackupStep.compressing,
            message: 'Comprimindo arquivo de backup...',
            progress: 0.6,
          );
        } catch (_) {
          // Ignorar se não estiver disponível
        }

        try {
          // Nome de saída customizado para Sybase full, para garantir timestamp/tipo no ZIP
          String? compressionOutputPath;
          if (schedule.databaseType == DatabaseType.sybase &&
              backupType == BackupType.full) {
            final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
            final baseName = p.basename(backupPath);
            compressionOutputPath = p.join(
              p.dirname(backupPath),
              '${baseName}_${backupType.name}_$ts.zip',
            );
          }

          // Usar método compress que detecta automaticamente arquivo ou diretório
          final compressionResult = await _compressionService.compress(
            path: backupPath,
            outputPath: compressionOutputPath,
            deleteOriginal: true,
          );

          if (compressionResult.isSuccess()) {
            backupPath = compressionResult.getOrNull()!.compressedPath;
            fileSize = compressionResult.getOrNull()!.compressedSize;
            await _log(history.id, 'info', 'Compressão concluída');
          } else {
            final failure = compressionResult.exceptionOrNull()!;
            final failureMessage =
                failure is Failure ? failure.message : failure.toString();

            LoggerService.error('Falha na compressão', failure);
            await _log(
              history.id,
              'error',
              'Falha na compressão: $failureMessage',
            );

            return rd.Failure(
              BackupFailure(
                message:
                    'Erro ao comprimir backup: $failureMessage. Verifique permissões da pasta de destino.',
                originalError: failure,
              ),
            );
          }
        } catch (e, stackTrace) {
          LoggerService.error('Erro inesperado durante compressão', e, stackTrace);
          final errorMessage =
              'Erro ao comprimir backup: $e. Verifique permissões da pasta de destino.';
          await _log(
            history.id,
            'error',
            errorMessage,
          );
          return rd.Failure(
            BackupFailure(
              message: errorMessage,
              originalError: e,
            ),
          );
        }
      }

      // Executar script SQL pós-backup se configurado
      if (schedule.postBackupScript != null &&
          schedule.postBackupScript!.trim().isNotEmpty) {
        await _log(history.id, 'info', 'Executando script SQL pós-backup');

        try {
          // Obter configuração do banco
          SqlServerConfig? sqlServerConfig;
          SybaseConfig? sybaseConfig;

          if (schedule.databaseType == DatabaseType.sqlServer) {
            final configResult = await _sqlServerConfigRepository.getById(
              schedule.databaseConfigId,
            );
            if (configResult.isSuccess()) {
              sqlServerConfig = configResult.getOrNull();
            }
          } else {
            final configResult = await _sybaseConfigRepository.getById(
              schedule.databaseConfigId,
            );
            if (configResult.isSuccess()) {
              sybaseConfig = configResult.getOrNull();
            }
          }

          final scriptResult = await _sqlScriptExecutionService.executeScript(
            databaseType: schedule.databaseType,
            sqlServerConfig: sqlServerConfig,
            sybaseConfig: sybaseConfig,
            script: schedule.postBackupScript!,
          );

          await scriptResult.fold(
            (_) async {
              await _log(history.id, 'info', 'Script SQL executado com sucesso');
            },
            (failure) async {
              final errorMessage = failure is Failure
                  ? failure.message
                  : failure.toString();
              LoggerService.warning(
                'Erro ao executar script SQL pós-backup: $errorMessage',
                failure,
              );
              await _log(
                history.id,
                'warning',
                'Script SQL pós-backup falhou: $errorMessage',
              );
              // Não falha o backup, apenas registra o erro como warning
            },
          );
        } catch (e, stackTrace) {
          LoggerService.error(
            'Erro inesperado ao executar script SQL',
            e,
            stackTrace,
          );
          await _log(
            history.id,
            'warning',
            'Erro ao executar script SQL pós-backup: $e',
          );
        }
      }

      // Atualizar histórico com sucesso
      final finishedAt = DateTime.now();
      history = history.copyWith(
        backupPath: backupPath,
        fileSize: fileSize,
        status: BackupStatus.success,
        finishedAt: finishedAt,
        durationSeconds: finishedAt.difference(history.startedAt).inSeconds,
      );

      await _backupHistoryRepository.update(history);
      await _log(history.id, 'info', 'Backup finalizado com sucesso');

      // Notificação por e-mail será enviada após upload para destinos remotos (FTP/Google Drive)
      // Isso é feito no SchedulerService após todos os uploads serem concluídos

      LoggerService.info('Backup concluído: ${history.backupPath}');
      return rd.Success(history);
    } catch (e, stackTrace) {
      LoggerService.error('Erro no backup', e, stackTrace);

      // Atualizar histórico com erro
      final finishedAt = DateTime.now();
      history = history.copyWith(
        status: BackupStatus.error,
        errorMessage: e.toString(),
        finishedAt: finishedAt,
        durationSeconds: finishedAt.difference(history.startedAt).inSeconds,
      );

      await _backupHistoryRepository.update(history);
      await _log(history.id, 'error', 'Erro no backup: $e');

      // Enviar notificação de erro por e-mail
      await _notificationService.notifyBackupComplete(history);

      return rd.Failure(
        BackupFailure(message: 'Erro ao executar backup: $e', originalError: e),
      );
    }
  }

  Future<void> _log(String historyId, String levelStr, String message) async {
    // Converter string para LogLevel
    LogLevel level;
    switch (levelStr) {
      case 'info':
        level = LogLevel.info;
        break;
      case 'warning':
        level = LogLevel.warning;
        break;
      case 'error':
        level = LogLevel.error;
        break;
      default:
        level = LogLevel.info;
    }

    final log = BackupLog(
      backupHistoryId: historyId,
      level: level,
      category: LogCategory.execution,
      message: message,
    );
    await _backupLogRepository.create(log);
  }
}
