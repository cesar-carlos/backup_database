import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;

import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/backup_destination.dart';
import '../../domain/entities/backup_history.dart';
import '../../domain/entities/backup_log.dart';
import '../../domain/repositories/repositories.dart';
import '../../infrastructure/external/scheduler/cron_parser.dart';
import '../../domain/use_cases/destinations/send_to_ftp.dart';
import '../../infrastructure/external/destinations/local_destination_service.dart'
    as local;
import '../../infrastructure/external/destinations/ftp_destination_service.dart'
    as ftp;
import '../../infrastructure/external/destinations/google_drive_destination_service.dart'
    as gd;
import 'backup_orchestrator_service.dart';
import 'notification_service.dart';

class SchedulerService {
  final IScheduleRepository _scheduleRepository;
  final IBackupDestinationRepository _destinationRepository;
  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupLogRepository _backupLogRepository;
  final BackupOrchestratorService _backupOrchestratorService;
  final local.LocalDestinationService _localDestinationService;
  final SendToFtp _sendToFtp;
  final ftp.FtpDestinationService _ftpDestinationService;
  final gd.GoogleDriveDestinationService _googleDriveDestinationService;
  final NotificationService _notificationService;

  final ScheduleCalculator _calculator = ScheduleCalculator();
  Timer? _checkTimer;
  bool _isRunning = false;
  final Set<String> _executingSchedules = {};

  SchedulerService({
    required IScheduleRepository scheduleRepository,
    required IBackupDestinationRepository destinationRepository,
    required IBackupHistoryRepository backupHistoryRepository,
    required IBackupLogRepository backupLogRepository,
    required BackupOrchestratorService backupOrchestratorService,
    required local.LocalDestinationService localDestinationService,
    required SendToFtp sendToFtp,
    required ftp.FtpDestinationService ftpDestinationService,
    required gd.GoogleDriveDestinationService googleDriveDestinationService,
    required NotificationService notificationService,
  }) : _scheduleRepository = scheduleRepository,
       _destinationRepository = destinationRepository,
       _backupHistoryRepository = backupHistoryRepository,
       _backupLogRepository = backupLogRepository,
       _backupOrchestratorService = backupOrchestratorService,
       _localDestinationService = localDestinationService,
       _sendToFtp = sendToFtp,
       _ftpDestinationService = ftpDestinationService,
       _googleDriveDestinationService = googleDriveDestinationService,
       _notificationService = notificationService;

  /// Inicia o serviço de agendamento
  Future<void> start() async {
    if (_isRunning) return;

    LoggerService.info('Iniciando serviço de agendamento');
    _isRunning = true;

    // Atualizar próximas execuções de todos os schedules
    await _updateAllNextRuns();

    // Verificar schedules a cada minuto
    _checkTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkSchedules(),
    );

    LoggerService.info('Serviço de agendamento iniciado');
  }

  /// Para o serviço de agendamento
  void stop() {
    LoggerService.info('Parando serviço de agendamento');
    _isRunning = false;
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// Atualiza a próxima execução de todos os schedules
  Future<void> _updateAllNextRuns() async {
    final result = await _scheduleRepository.getEnabled();

    result.fold(
      (schedules) async {
        for (final schedule in schedules) {
          final nextRunAt = _calculator.getNextRunTime(schedule);
          if (nextRunAt != null) {
            LoggerService.info(
              'Atualizando schedule ${schedule.name}: '
              'nextRunAt atual = ${schedule.nextRunAt}, '
              'novo nextRunAt = $nextRunAt',
            );
            await _scheduleRepository.update(
              schedule.copyWith(nextRunAt: nextRunAt),
            );
          }
        }
        LoggerService.info('${schedules.length} schedules atualizados');
      },
      (exception) {
        final failure = exception as Failure;
        LoggerService.error('Erro ao atualizar schedules: ${failure.message}');
      },
    );
  }

  /// Verifica schedules pendentes
  Future<void> _checkSchedules() async {
    if (!_isRunning) return;

    final result = await _scheduleRepository.getEnabled();

    result.fold((schedules) async {
      for (final schedule in schedules) {
        // Evitar execuções duplicadas do mesmo schedule
        if (_executingSchedules.contains(schedule.id)) {
          continue;
        }

        if (_calculator.shouldRunNow(schedule)) {
          // Marcar como executando antes de iniciar
          _executingSchedules.add(schedule.id);

          // Atualizar nextRunAt imediatamente para evitar execuções duplicadas
          final nextRunAt = _calculator.getNextRunTime(schedule);
          if (nextRunAt != null) {
            await _scheduleRepository.update(
              schedule.copyWith(nextRunAt: nextRunAt),
            );
          }

          // Executar em background para não bloquear
          unawaited(
            _executeScheduledBackup(schedule)
                .then((_) {
                  _executingSchedules.remove(schedule.id);
                })
                .catchError((error) {
                  _executingSchedules.remove(schedule.id);
                }),
          );
        }
      }
    }, (failure) => null);
  }

  /// Executa o backup agendado
  Future<rd.Result<void>> _executeScheduledBackup(Schedule schedule) async {
    LoggerService.info(
      'Executando backup agendado: ${schedule.name} '
      '(nextRunAt: ${schedule.nextRunAt}, now: ${DateTime.now()})',
    );

    late String tempBackupPath;
    bool shouldDeleteTempFile = false;

    try {
      // Obter destinos
      final destinations = await _getDestinations(schedule.destinationIds);
      final localDestination = destinations
          .where((d) => d.type == DestinationType.local)
          .firstOrNull;

      String outputDirectory;

      if (localDestination != null) {
        // Se houver destino local, usar o caminho dele
        final localConfig = local.LocalDestinationConfig(
          path:
              (jsonDecode(localDestination.config)
                      as Map<String, dynamic>)['path']
                  as String,
          createSubfoldersByDate:
              (jsonDecode(localDestination.config)
                      as Map<String, dynamic>)['createSubfoldersByDate']
                  as bool? ??
              true,
          retentionDays:
              (jsonDecode(localDestination.config)
                      as Map<String, dynamic>)['retentionDays']
                  as int? ??
              30,
        );
        
        // Validar que o caminho não está vazio
        if (localConfig.path.isEmpty) {
          final errorMessage =
              'Caminho do destino local está vazio para o agendamento: ${schedule.name}';
          LoggerService.error(errorMessage);
          return rd.Failure(ValidationFailure(message: errorMessage));
        }
        
        outputDirectory = localConfig.path;
      } else {
        // Validar que o caminho do agendamento não está vazio
        if (schedule.backupFolder.isEmpty) {
          final errorMessage =
              'Pasta de backup não configurada para o agendamento: ${schedule.name}';
          LoggerService.error(errorMessage);
          return rd.Failure(ValidationFailure(message: errorMessage));
        }
        
        // Usar pasta de backup configurada no agendamento
        final backupDir = Directory(schedule.backupFolder);
        if (!await backupDir.exists()) {
          try {
            await backupDir.create(recursive: true);
          } catch (e) {
            final errorMessage =
                'Erro ao criar pasta de backup: ${schedule.backupFolder}';
            LoggerService.error(errorMessage, e);
            return rd.Failure(ValidationFailure(message: errorMessage));
          }
        }

        // Validar permissão de escrita
        final hasPermission = await _checkWritePermission(backupDir);
        if (!hasPermission) {
          final errorMessage =
              'Sem permissão de escrita na pasta de backup: ${schedule.backupFolder}';
          LoggerService.error(errorMessage);
          return rd.Failure(ValidationFailure(message: errorMessage));
        }

        outputDirectory = backupDir.path;
        shouldDeleteTempFile = true;
        LoggerService.info(
          'Nenhum destino local configurado, usando pasta de backup do agendamento: $outputDirectory',
        );
      }
      
      // Validação final: garantir que outputDirectory não está vazio
      if (outputDirectory.isEmpty) {
        final errorMessage =
            'Caminho de saída do backup está vazio para o agendamento: ${schedule.name}';
        LoggerService.error(errorMessage);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }

      // Executar backup
      final backupResult = await _backupOrchestratorService.executeBackup(
        schedule: schedule,
        outputDirectory: outputDirectory,
      );

      if (backupResult.isError()) {
        // Em caso de erro no backup, a notificação já foi enviada pelo BackupOrchestratorService
        // Não há upload para fazer, então o email é enviado imediatamente
        return rd.Failure(backupResult.exceptionOrNull()!);
      }

      final backupHistory = backupResult.getOrNull()!;
      tempBackupPath = backupHistory.backupPath;

      // Verificar se há destinos remotos (FTP ou Google Drive)
      final hasRemoteDestinations = destinations.any(
        (d) =>
            d.type == DestinationType.ftp ||
            d.type == DestinationType.googleDrive,
      );

      // Enviar para destinos configurados e coletar erros
      final List<String> uploadErrors = [];
      bool hasCriticalUploadError = false;

      for (final destination in destinations) {
        if (destination.type == DestinationType.local) {
          // Destino local já foi salvo durante o backup
          continue;
        }

        final sendResult = await _sendToDestination(
          sourceFilePath: backupHistory.backupPath,
          destination: destination,
        );

        sendResult.fold(
          (_) {
            // Sucesso
          },
          (failure) {
            final failureMessage = failure is Failure
                ? failure.message
                : failure.toString();
            final errorMessage =
                'Falha ao enviar para ${destination.name}: $failureMessage';
            uploadErrors.add(errorMessage);
            LoggerService.error(errorMessage, failure);
            hasCriticalUploadError = true;
          },
        );
      }

      // Se houver erros críticos de upload, marcar backup como erro
      if (hasCriticalUploadError) {
        final errorMessage = uploadErrors.join('\n');
        final finishedAt = DateTime.now();
        final failedHistory = backupHistory.copyWith(
          status: BackupStatus.error,
          errorMessage:
              'Backup concluído localmente, mas falhou ao enviar para destinos remotos:\n$errorMessage',
          finishedAt: finishedAt,
          durationSeconds: finishedAt
              .difference(backupHistory.startedAt)
              .inSeconds,
        );
        await _backupHistoryRepository.update(failedHistory);

        // Gravar log de erro no banco
        await _log(
          backupHistory.id,
          'error',
          'Falha ao enviar backup para destinos remotos:\n$errorMessage',
        );

        // Enviar notificação por email
        final notifyResult = await _notificationService.notifyBackupComplete(
          failedHistory,
        );
        notifyResult.fold(
          (sent) {
            if (sent) {
              LoggerService.info('Notificação de erro enviada por email');
            } else {
              LoggerService.warning(
                'Notificação de erro não foi enviada (email desabilitado ou configuração inválida)',
              );
            }
          },
          (failure) {
            LoggerService.error(
              'Erro ao enviar notificação por email',
              failure,
            );
          },
        );

        final failure = BackupFailure(
          message:
              'Falha ao enviar backup para destinos remotos:\n$errorMessage',
        );
        LoggerService.error(
          'Backup marcado como erro devido a falhas no upload',
          failure,
        );
        return rd.Failure(failure);
      }

      // Se houver erros não críticos (apenas avisos), notificar mas manter sucesso
      if (uploadErrors.isNotEmpty) {
        final warningMessage =
            'O backup foi concluído, mas houve avisos:\n\n'
            '${uploadErrors.join('\n')}';

        await _notificationService.sendWarning(
          databaseName: schedule.name,
          message: warningMessage,
        );
      }

      // Enviar notificação por e-mail apenas após upload para destinos remotos
      // Se não houver destinos remotos, enviar imediatamente
      if (hasRemoteDestinations) {
        LoggerService.info(
          'Uploads para destinos remotos concluídos, enviando notificação por e-mail',
        );
      }
      await _notificationService.notifyBackupComplete(backupHistory);

      // Se usamos pasta temporária e não há destino local, deletar arquivo após enviar
      if (shouldDeleteTempFile) {
        try {
          final entityType = FileSystemEntity.typeSync(tempBackupPath);

          switch (entityType) {
            case FileSystemEntityType.file:
              final tempFile = File(tempBackupPath);
              if (tempFile.existsSync()) {
                await tempFile.delete();
                LoggerService.info('Arquivo temporário deletado: $tempBackupPath');
              }
              break;
            case FileSystemEntityType.directory:
              final tempDir = Directory(tempBackupPath);
              if (tempDir.existsSync()) {
                await tempDir.delete(recursive: true);
                LoggerService.info('Diretório temporário deletado: $tempBackupPath');
              }
              break;
            default:
              LoggerService.debug(
                'Arquivo temporário não encontrado para exclusão: $tempBackupPath',
              );
          }
        } catch (e) {
          LoggerService.warning('Erro ao deletar arquivo temporário: $e');
        }
      }

      // Atualizar próxima execução
      // Para agendamentos por intervalo, é necessário calcular nextRunAt
      // APÓS atualizar lastRunAt, pois o cálculo depende dele
      final now = DateTime.now();
      final scheduleWithLastRun = schedule.copyWith(lastRunAt: now);
      final nextRunAt = _calculator.getNextRunTime(scheduleWithLastRun);
      final updatedSchedule = scheduleWithLastRun.copyWith(
        nextRunAt: nextRunAt,
      );
      await _scheduleRepository.update(updatedSchedule);

      LoggerService.info(
        'Próxima execução de ${schedule.name} agendada para: $nextRunAt '
        '(baseado em lastRunAt: $now, tipo: ${schedule.scheduleType})',
      );

      // Limpar backups antigos
      await _cleanOldBackups(destinations, backupHistory.id);

      LoggerService.info('Backup agendado concluído: ${schedule.name}');
      return rd.Success(());
    } catch (e, stackTrace) {
      LoggerService.error('Erro no backup agendado', e, stackTrace);
      return rd.Failure(
        BackupFailure(message: 'Erro no backup agendado: $e', originalError: e),
      );
    }
  }

  Future<List<BackupDestination>> _getDestinations(List<String> ids) async {
    final destinations = <BackupDestination>[];

    for (final id in ids) {
      final result = await _destinationRepository.getById(id);
      result.fold(
        (destination) => destinations.add(destination),
        (failure) => null,
      );
    }

    return destinations;
  }

  Future<rd.Result<void>> _sendToDestination({
    required String sourceFilePath,
    required BackupDestination destination,
  }) async {
    try {
      final configJson = jsonDecode(destination.config) as Map<String, dynamic>;

      switch (destination.type) {
        case DestinationType.local:
          // Já foi salvo localmente
          return rd.Success(());

        case DestinationType.ftp:
          final config = ftp.FtpDestinationConfig(
            host: configJson['host'] as String,
            port: configJson['port'] as int? ?? 21,
            username: configJson['username'] as String,
            password: configJson['password'] as String,
            remotePath: configJson['remotePath'] as String? ?? '/',
            useFtps: configJson['useFtps'] as bool? ?? false,
          );

          LoggerService.info(
            'Enviando backup para FTP: ${destination.name} (${config.host})',
          );

          final uploadResult = await _sendToFtp.call(
            sourceFilePath: sourceFilePath,
            config: config,
          );

          return uploadResult.fold(
            (result) {
              LoggerService.info(
                'Upload FTP concluído com sucesso: ${result.remotePath} '
                '(${_formatBytes(result.fileSize)} em ${result.duration.inSeconds}s)',
              );
              return rd.Success(());
            },
            (failure) {
              LoggerService.error(
                'Erro ao enviar backup para FTP ${destination.name}',
                failure,
              );
              return rd.Failure(failure);
            },
          );

        case DestinationType.googleDrive:
          final config = gd.GoogleDriveDestinationConfig(
            folderId: configJson['folderId'] as String,
            folderName: configJson['folderName'] as String? ?? 'Backups',
          );
          final result = await _googleDriveDestinationService.upload(
            sourceFilePath: sourceFilePath,
            config: config,
          );
          return result.fold(
            (_) => rd.Success(()),
            (failure) => rd.Failure(failure),
          );
      }
    } catch (e) {
      LoggerService.error('Erro ao enviar para ${destination.name}: $e', e);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao enviar para ${destination.name}: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<void> _cleanOldBackups(
    List<BackupDestination> destinations,
    String backupHistoryId,
  ) async {
    for (final destination in destinations) {
      try {
        final configJson =
            jsonDecode(destination.config) as Map<String, dynamic>;

        switch (destination.type) {
          case DestinationType.local:
            final config = local.LocalDestinationConfig(
              path: configJson['path'] as String,
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            await _localDestinationService.cleanOldBackups(config: config);
            break;

          case DestinationType.ftp:
            final config = ftp.FtpDestinationConfig(
              host: configJson['host'] as String,
              port: configJson['port'] as int? ?? 21,
              username: configJson['username'] as String,
              password: configJson['password'] as String,
              remotePath: configJson['remotePath'] as String? ?? '/',
              useFtps: configJson['useFtps'] as bool? ?? false,
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final cleanResult = await _ftpDestinationService.cleanOldBackups(
              config: config,
            );
            cleanResult.fold(
              (_) {
                // Sucesso
              },
              (exception) async {
                LoggerService.error(
                  'Erro ao limpar backups FTP em ${destination.name}',
                  exception,
                );
                final failureMessage = exception is Failure
                    ? exception.message
                    : exception.toString();

                // Gravar log de erro no banco
                await _log(
                  backupHistoryId,
                  'error',
                  'Erro ao limpar backups antigos no FTP ${destination.name}: $failureMessage',
                );

                // Enviar notificação por email
                await _notificationService.sendWarning(
                  databaseName: destination.name,
                  message:
                      'Erro ao limpar backups antigos no FTP ${destination.name}: $failureMessage',
                );
              },
            );
            break;

          case DestinationType.googleDrive:
            final config = gd.GoogleDriveDestinationConfig(
              folderId: configJson['folderId'] as String,
              folderName: configJson['folderName'] as String? ?? 'Backups',
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final cleanResult = await _googleDriveDestinationService
                .cleanOldBackups(config: config);
            cleanResult.fold(
              (_) {
                // Sucesso
              },
              (exception) async {
                LoggerService.error(
                  'Erro ao limpar backups Google Drive em ${destination.name}',
                  exception,
                );
                final failureMessage = exception is Failure
                    ? exception.message
                    : exception.toString();

                // Gravar log de erro no banco
                await _log(
                  backupHistoryId,
                  'error',
                  'Erro ao limpar backups antigos no Google Drive ${destination.name}: $failureMessage',
                );

                // Enviar notificação por email
                await _notificationService.sendWarning(
                  databaseName: destination.name,
                  message:
                      'Erro ao limpar backups antigos no Google Drive ${destination.name}: $failureMessage',
                );
              },
            );
            break;
        }
      } catch (e, stackTrace) {
        LoggerService.error(
          'Erro ao limpar backups em ${destination.name}',
          e,
          stackTrace,
        );

        // Gravar log de erro no banco
        await _log(
          backupHistoryId,
          'error',
          'Erro ao limpar backups antigos em ${destination.name}: $e',
        );

        // Enviar notificação por email
        await _notificationService.sendWarning(
          databaseName: destination.name,
          message: 'Erro ao limpar backups antigos em ${destination.name}: $e',
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Executa um backup manualmente
  Future<rd.Result<void>> executeNow(String scheduleId) async {
    final result = await _scheduleRepository.getById(scheduleId);

    return result.fold(
      (schedule) async => await _executeScheduledBackup(schedule),
      (failure) => rd.Failure(failure),
    );
  }

  /// Adiciona/atualiza um schedule no serviço
  Future<rd.Result<void>> refreshSchedule(String scheduleId) async {
    final result = await _scheduleRepository.getById(scheduleId);

    return result.fold((schedule) async {
      // Calcular e atualizar próxima execução
      final nextRunAt = _calculator.getNextRunTime(schedule);
      if (nextRunAt != null) {
        await _scheduleRepository.update(
          schedule.copyWith(nextRunAt: nextRunAt),
        );
      }
      return rd.Success(());
    }, (failure) => rd.Failure(failure));
  }

  bool get isRunning => _isRunning;

  Future<bool> _checkWritePermission(Directory directory) async {
    try {
      // Tentar criar um arquivo temporário para testar permissão
      final testFileName =
          '.backup_permission_test_${DateTime.now().millisecondsSinceEpoch}';
      final testFile = File(
        '${directory.path}${Platform.pathSeparator}$testFileName',
      );

      // Tentar escrever no arquivo
      await testFile.writeAsString('test');

      // Se conseguiu escrever, deletar o arquivo
      if (await testFile.exists()) {
        await testFile.delete();
        return true;
      }

      return false;
    } catch (e) {
      LoggerService.warning(
        'Erro ao verificar permissão de escrita na pasta ${directory.path}: $e',
      );
      return false;
    }
  }

  Future<void> _log(String historyId, String levelStr, String message) async {
    try {
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
    } catch (e) {
      LoggerService.warning('Erro ao gravar log no banco: $e');
    }
  }
}
