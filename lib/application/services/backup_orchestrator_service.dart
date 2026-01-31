import 'dart:io';

import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/application/services/notification_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_compression_service.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_script_execution_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class BackupOrchestratorService {
  BackupOrchestratorService({
    required ISqlServerConfigRepository sqlServerConfigRepository,
    required ISybaseConfigRepository sybaseConfigRepository,
    required IPostgresConfigRepository postgresConfigRepository,
    required IBackupHistoryRepository backupHistoryRepository,
    required IBackupLogRepository backupLogRepository,
    required ISqlServerBackupService sqlServerBackupService,
    required ISybaseBackupService sybaseBackupService,
    required IPostgresBackupService postgresBackupService,
    required ICompressionService compressionService,
    required ISqlScriptExecutionService sqlScriptExecutionService,
    required NotificationService notificationService,
  }) : _sqlServerConfigRepository = sqlServerConfigRepository,
       _sybaseConfigRepository = sybaseConfigRepository,
       _postgresConfigRepository = postgresConfigRepository,
       _backupHistoryRepository = backupHistoryRepository,
       _backupLogRepository = backupLogRepository,
       _sqlServerBackupService = sqlServerBackupService,
       _sybaseBackupService = sybaseBackupService,
       _postgresBackupService = postgresBackupService,
       _compressionService = compressionService,
       _sqlScriptExecutionService = sqlScriptExecutionService,
       _notificationService = notificationService;
  final ISqlServerConfigRepository _sqlServerConfigRepository;
  final ISybaseConfigRepository _sybaseConfigRepository;
  final IPostgresConfigRepository _postgresConfigRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupLogRepository _backupLogRepository;
  final ISqlServerBackupService _sqlServerBackupService;
  final ISybaseBackupService _sybaseBackupService;
  final IPostgresBackupService _postgresBackupService;
  final ICompressionService _compressionService;
  final ISqlScriptExecutionService _sqlScriptExecutionService;
  final NotificationService _notificationService;

  Future<rd.Result<BackupHistory>> executeBackup({
    required Schedule schedule,
    required String outputDirectory,
  }) async {
    LoggerService.info('Iniciando backup para schedule: ${schedule.name}');

    if (outputDirectory.isEmpty) {
      final errorMessage =
          'Caminho de saída do backup está vazio para o agendamento: '
          '${schedule.name}';
      LoggerService.error(errorMessage);
      return rd.Failure(ValidationFailure(message: errorMessage));
    }

    final backupType =
        (schedule.databaseType != DatabaseType.postgresql &&
            schedule.backupType == BackupType.fullSingle)
        ? BackupType.full
        : schedule.backupType;

    final typeFolderName = backupType.displayName;
    final typeOutputDirectory = p.join(outputDirectory, typeFolderName);

    if (typeOutputDirectory.isEmpty) {
      final errorMessage =
          'Caminho de saída do backup por tipo está vazio para o '
          'agendamento: ${schedule.name}';
      LoggerService.error(errorMessage);
      return rd.Failure(ValidationFailure(message: errorMessage));
    }

    final typeOutputDir = Directory(typeOutputDirectory);
    if (!await typeOutputDir.exists()) {
      try {
        await typeOutputDir.create(recursive: true);
      } on Object catch (e) {
        final errorMessage =
            'Erro ao criar pasta de backup por tipo: '
            '$typeOutputDirectory';
        LoggerService.error(errorMessage, e);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }
    }

    LoggerService.info(
      'Diretório de backup por tipo: $typeOutputDirectory '
      '(Tipo: ${backupType.displayName})',
    );

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
      } else if (schedule.databaseType == DatabaseType.sybase) {
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
            'Schedule: ${schedule.name}, '
                'ConfigId: ${schedule.databaseConfigId}, Erro: $errorMessage',
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
      } else if (schedule.databaseType == DatabaseType.postgresql) {
        final configResult = await _postgresConfigRepository.getById(
          schedule.databaseConfigId,
        );
        if (configResult.isError()) {
          final failure = configResult.exceptionOrNull();
          final errorMessage = failure is Failure
              ? failure.message
              : 'Configuração PostgreSQL não encontrada';
          LoggerService.error(
            'Falha ao buscar configuração PostgreSQL',
            'Schedule: ${schedule.name}, '
                'ConfigId: ${schedule.databaseConfigId}, Erro: $errorMessage',
          );
          throw Exception(errorMessage);
        }

        final backupResult = await _postgresBackupService.executeBackup(
          config: configResult.getOrNull()!,
          outputDirectory: typeOutputDirectory,
          backupType: backupType,
          verifyAfterBackup: schedule.verifyAfterBackup,
        );

        if (backupResult.isError()) {
          final failure = backupResult.exceptionOrNull()! as Failure;
          throw Exception(failure.message);
        }

        backupPath = backupResult.getOrNull()!.backupPath;
        fileSize = backupResult.getOrNull()!.fileSize;
      } else {
        throw Exception(
          'Tipo de banco de dados não suportado: ${schedule.databaseType}',
        );
      }

      await _log(history.id, 'info', 'Backup do banco concluído');

      try {
        final progressProvider = getIt<BackupProgressProvider>();
        progressProvider.updateProgress(
          step: BackupStep.executingBackup,
          message: 'Backup do banco concluído',
          progress: 0.5,
        );
      } on Object catch (e, s) {
        LoggerService.warning('Erro ao atualizar progresso', e, s);
      }

      if (schedule.compressionFormat != CompressionFormat.none) {
        await _log(history.id, 'info', 'Iniciando compressão');

        try {
          final progressProvider = getIt<BackupProgressProvider>();
          progressProvider.updateProgress(
            step: BackupStep.compressing,
            message: 'Comprimindo arquivo de backup...',
            progress: 0.6,
          );
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao atualizar progresso', e, s);
        }

        try {
          String? compressionOutputPath;
          if (schedule.databaseType == DatabaseType.sybase &&
              backupType == BackupType.full) {
            final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
            final baseName = p.basename(backupPath);
            final extension =
                schedule.compressionFormat == CompressionFormat.rar
                ? '.rar'
                : '.zip';
            compressionOutputPath = p.join(
              p.dirname(backupPath),
              '${baseName}_${backupType.name}_$ts$extension',
            );
          }

          final compressionResult = await _compressionService.compress(
            path: backupPath,
            outputPath: compressionOutputPath,
            deleteOriginal: true,
            format: schedule.compressionFormat,
          );

          if (compressionResult.isSuccess()) {
            backupPath = compressionResult.getOrNull()!.compressedPath;
            fileSize = compressionResult.getOrNull()!.compressedSize;

            await _log(history.id, 'info', 'Compressão concluída');

            try {
              final progressProvider = getIt<BackupProgressProvider>();
              progressProvider.updateProgress(
                step: BackupStep.compressing,
                message: 'Compressão concluída',
                progress: 0.8,
              );
            } on Object catch (e, s) {
              LoggerService.warning('Erro ao atualizar progresso', e, s);
            }
          } else {
            final failure = compressionResult.exceptionOrNull()!;
            final failureMessage = failure is Failure
                ? failure.message
                : failure.toString();

            LoggerService.error('Falha na compressão', failure);
            await _log(
              history.id,
              'error',
              'Falha na compressão: $failureMessage',
            );

            return rd.Failure(
              BackupFailure(
                message:
                    'Erro ao comprimir backup: $failureMessage. '
                    'Verifique permissões da pasta de destino.',
                originalError: failure,
              ),
            );
          }
        } on Object catch (e, stackTrace) {
          LoggerService.error(
            'Erro inesperado durante compressão',
            e,
            stackTrace,
          );
          final errorMessage =
              'Erro ao comprimir backup: $e. '
              'Verifique permissões da pasta de destino.';
          await _log(history.id, 'error', errorMessage);
          return rd.Failure(
            BackupFailure(message: errorMessage, originalError: e),
          );
        }
      }

      if (schedule.postBackupScript != null &&
          schedule.postBackupScript!.trim().isNotEmpty) {
        await _log(history.id, 'info', 'Executando script SQL pós-backup');

        try {
          SqlServerConfig? sqlServerConfig;
          SybaseConfig? sybaseConfig;
          PostgresConfig? postgresConfig;

          if (schedule.databaseType == DatabaseType.sqlServer) {
            final configResult = await _sqlServerConfigRepository.getById(
              schedule.databaseConfigId,
            );
            if (configResult.isSuccess()) {
              sqlServerConfig = configResult.getOrNull();
            }
          } else if (schedule.databaseType == DatabaseType.sybase) {
            final configResult = await _sybaseConfigRepository.getById(
              schedule.databaseConfigId,
            );
            if (configResult.isSuccess()) {
              sybaseConfig = configResult.getOrNull();
            }
          } else if (schedule.databaseType == DatabaseType.postgresql) {
            final configResult = await _postgresConfigRepository.getById(
              schedule.databaseConfigId,
            );
            if (configResult.isSuccess()) {
              postgresConfig = configResult.getOrNull();
            }
          }

          final scriptResult = await _sqlScriptExecutionService.executeScript(
            databaseType: schedule.databaseType,
            sqlServerConfig: sqlServerConfig,
            sybaseConfig: sybaseConfig,
            postgresConfig: postgresConfig,
            script: schedule.postBackupScript!,
          );

          await scriptResult.fold(
            (_) async {
              await _log(
                history.id,
                'info',
                'Script SQL executado com sucesso',
              );
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
            },
          );
        } on Object catch (e, stackTrace) {
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

      LoggerService.info('Backup concluído: ${history.backupPath}');
      return rd.Success(history);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro no backup', e, stackTrace);

      final finishedAt = DateTime.now();
      history = history.copyWith(
        status: BackupStatus.error,
        errorMessage: e.toString(),
        finishedAt: finishedAt,
        durationSeconds: finishedAt.difference(history.startedAt).inSeconds,
      );

      await _backupHistoryRepository.update(history);
      await _log(history.id, 'error', 'Erro no backup: $e');

      await _notificationService.notifyBackupComplete(history);

      return rd.Failure(
        BackupFailure(message: 'Erro ao executar backup: $e', originalError: e),
      );
    }
  }

  Future<void> _log(String historyId, String levelStr, String message) async {
    LogLevel level;
    switch (levelStr) {
      case 'info':
        level = LogLevel.info;
      case 'warning':
        level = LogLevel.warning;
      case 'error':
        level = LogLevel.error;
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
