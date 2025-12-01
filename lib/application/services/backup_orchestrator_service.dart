import 'package:result_dart/result_dart.dart' as rd;

import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';
import '../../core/di/service_locator.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/backup_history.dart';
import '../../domain/entities/backup_log.dart';
import '../../domain/repositories/repositories.dart';
import '../../infrastructure/external/process/sql_server_backup_service.dart';
import '../../infrastructure/external/process/sybase_backup_service.dart';
import '../../infrastructure/external/compression/compression_service.dart';
import '../providers/backup_progress_provider.dart';
import 'notification_service.dart';

class BackupOrchestratorService {
  final ISqlServerConfigRepository _sqlServerConfigRepository;
  final ISybaseConfigRepository _sybaseConfigRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupLogRepository _backupLogRepository;
  final SqlServerBackupService _sqlServerBackupService;
  final SybaseBackupService _sybaseBackupService;
  final CompressionService _compressionService;
  final NotificationService _notificationService;

  BackupOrchestratorService({
    required ISqlServerConfigRepository sqlServerConfigRepository,
    required ISybaseConfigRepository sybaseConfigRepository,
    required IBackupHistoryRepository backupHistoryRepository,
    required IBackupLogRepository backupLogRepository,
    required SqlServerBackupService sqlServerBackupService,
    required SybaseBackupService sybaseBackupService,
    required CompressionService compressionService,
    required NotificationService notificationService,
  }) : _sqlServerConfigRepository = sqlServerConfigRepository,
       _sybaseConfigRepository = sybaseConfigRepository,
       _backupHistoryRepository = backupHistoryRepository,
       _backupLogRepository = backupLogRepository,
       _sqlServerBackupService = sqlServerBackupService,
       _sybaseBackupService = sybaseBackupService,
       _compressionService = compressionService,
       _notificationService = notificationService;

  Future<rd.Result<BackupHistory>> executeBackup({
    required Schedule schedule,
    required String outputDirectory,
  }) async {
    LoggerService.info('Iniciando backup para schedule: ${schedule.name}');

    // Criar registro de histórico com status "running"
    var history = BackupHistory(
      scheduleId: schedule.id,
      databaseName: schedule.name,
      databaseType: schedule.databaseType.name,
      backupPath: '',
      fileSize: 0,
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
          outputDirectory: outputDirectory,
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
          outputDirectory: outputDirectory,
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
          // Usar método compress que detecta automaticamente arquivo ou diretório
          final compressionResult = await _compressionService.compress(
            path: backupPath,
            deleteOriginal: true,
          );

          if (compressionResult.isSuccess()) {
            backupPath = compressionResult.getOrNull()!.compressedPath;
            fileSize = compressionResult.getOrNull()!.compressedSize;
            await _log(history.id, 'info', 'Compressão concluída');
          } else {
            final failure = compressionResult.exceptionOrNull()! as Failure;
            LoggerService.error('Falha na compressão', failure);
            await _log(
              history.id,
              'warning',
              'Falha na compressão: ${failure.message}\n'
              'O backup original foi mantido sem compressão.',
            );
            // Não falha o backup completo, apenas registra o aviso
          }
        } catch (e, stackTrace) {
          LoggerService.error('Erro inesperado durante compressão', e, stackTrace);
          await _log(
            history.id,
            'error',
            'Erro inesperado durante compressão: $e\n'
            'O backup original foi mantido sem compressão.',
          );
          // Não falha o backup completo, apenas registra o erro
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
