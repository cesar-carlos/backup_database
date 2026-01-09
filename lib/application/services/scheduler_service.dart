import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;

import '../../core/constants/license_features.dart';
import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/backup_destination.dart';
import '../../domain/entities/backup_history.dart';
import '../../domain/entities/backup_log.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/i_license_validation_service.dart';
import '../../infrastructure/external/scheduler/cron_parser.dart';
import '../../domain/use_cases/destinations/send_to_ftp.dart';
import '../../infrastructure/external/destinations/local_destination_service.dart'
    as local;
import '../../infrastructure/external/destinations/ftp_destination_service.dart'
    as ftp;
import '../../infrastructure/external/destinations/google_drive_destination_service.dart'
    as gd;
import '../../infrastructure/external/dropbox/dropbox_destination_service.dart'
    as dropbox;
import '../../infrastructure/external/nextcloud/nextcloud_destination_service.dart'
    as nextcloud;
import '../../domain/use_cases/destinations/send_to_dropbox.dart';
import '../../domain/use_cases/destinations/send_to_nextcloud.dart';
import '../../core/di/service_locator.dart';
import '../providers/backup_progress_provider.dart';
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
  final dropbox.DropboxDestinationService _dropboxDestinationService;
  final SendToDropbox _sendToDropbox;
  final nextcloud.NextcloudDestinationService _nextcloudDestinationService;
  final SendToNextcloud _sendToNextcloud;
  final NotificationService _notificationService;
  final ILicenseValidationService _licenseValidationService;

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
    required dropbox.DropboxDestinationService dropboxDestinationService,
    required SendToDropbox sendToDropbox,
    required nextcloud.NextcloudDestinationService nextcloudDestinationService,
    required SendToNextcloud sendToNextcloud,
    required NotificationService notificationService,
    required ILicenseValidationService licenseValidationService,
  }) : _scheduleRepository = scheduleRepository,
       _destinationRepository = destinationRepository,
       _backupHistoryRepository = backupHistoryRepository,
       _backupLogRepository = backupLogRepository,
       _backupOrchestratorService = backupOrchestratorService,
       _localDestinationService = localDestinationService,
       _sendToFtp = sendToFtp,
       _ftpDestinationService = ftpDestinationService,
       _googleDriveDestinationService = googleDriveDestinationService,
       _dropboxDestinationService = dropboxDestinationService,
       _sendToDropbox = sendToDropbox,
       _nextcloudDestinationService = nextcloudDestinationService,
       _sendToNextcloud = sendToNextcloud,
       _notificationService = notificationService,
       _licenseValidationService = licenseValidationService;

  Future<rd.Result<void>> _ensureDestinationFeatureAllowed(
    BackupDestination destination,
  ) async {
    String? requiredFeature;
    switch (destination.type) {
      case DestinationType.googleDrive:
        requiredFeature = LicenseFeatures.googleDrive;
        break;
      case DestinationType.dropbox:
        requiredFeature = LicenseFeatures.dropbox;
        break;
      case DestinationType.nextcloud:
        requiredFeature = LicenseFeatures.nextcloud;
        break;
      case DestinationType.local:
      case DestinationType.ftp:
        requiredFeature = null;
        break;
    }

    if (requiredFeature == null) {
      return rd.Success(());
    }

    final allowedResult = await _licenseValidationService.isFeatureAllowed(
      requiredFeature,
    );
    final allowed = allowedResult.getOrElse((_) => false);
    if (!allowed) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Destino ${destination.name} requer licença (${destination.type.name}).',
        ),
      );
    }

    return rd.Success(());
  }

  Future<void> start() async {
    if (_isRunning) return;

    LoggerService.info('Iniciando serviço de agendamento');
    _isRunning = true;

    await _updateAllNextRuns();

    _checkTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkSchedules(),
    );

    LoggerService.info('Serviço de agendamento iniciado');
  }

  void stop() {
    LoggerService.info('Parando serviço de agendamento');
    _isRunning = false;
    _checkTimer?.cancel();
    _checkTimer = null;
  }

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

  Future<void> _checkSchedules() async {
    if (!_isRunning) return;

    final result = await _scheduleRepository.getEnabled();

    result.fold((schedules) async {
      for (final schedule in schedules) {
        final isExecuting = _executingSchedules.contains(schedule.id);
        final shouldRun = _calculator.shouldRunNow(schedule);

        if (isExecuting) {
          continue;
        }

        if (shouldRun) {
          _executingSchedules.add(schedule.id);

          final nextRunAt = _calculator.getNextRunTime(schedule);
          if (nextRunAt != null) {
            await _scheduleRepository.update(
              schedule.copyWith(nextRunAt: nextRunAt),
            );
          }

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

  Future<rd.Result<void>> _executeScheduledBackup(Schedule schedule) async {
    LoggerService.info(
      'Executando backup agendado: ${schedule.name} '
      '(nextRunAt: ${schedule.nextRunAt}, now: ${DateTime.now()})',
    );

    late String tempBackupPath;
    bool shouldDeleteTempFile = false;

    try {
      final destinations = await _getDestinations(schedule.destinationIds);

      if (schedule.backupFolder.isEmpty) {
        final errorMessage =
            'Pasta de backup não configurada para o agendamento: ${schedule.name}';
        LoggerService.error(errorMessage);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }

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

      final hasPermission = await _checkWritePermission(backupDir);
      if (!hasPermission) {
        final errorMessage =
            'Sem permissão de escrita na pasta de backup: ${schedule.backupFolder}';
        LoggerService.error(errorMessage);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }

      final outputDirectory = backupDir.path;
      shouldDeleteTempFile = true;
      LoggerService.info(
        'Usando pasta temporária de backup: $outputDirectory',
      );

      if (outputDirectory.isEmpty) {
        final errorMessage =
            'Caminho de saída do backup está vazio para o agendamento: ${schedule.name}';
        LoggerService.error(errorMessage);
        return rd.Failure(ValidationFailure(message: errorMessage));
      }

      final backupResult = await _backupOrchestratorService.executeBackup(
        schedule: schedule,
        outputDirectory: outputDirectory,
      );

      if (backupResult.isError()) {
        try {
          final progressProvider = getIt<BackupProgressProvider>();
          final error = backupResult.exceptionOrNull()!;
          final errorMessage = error is Failure
              ? error.message
              : error.toString();
          progressProvider.failBackup(errorMessage);
        } catch (_) {
          // Ignorar se não estiver disponível
        }
        return rd.Failure(backupResult.exceptionOrNull()!);
      }

      final backupHistory = backupResult.getOrNull()!;
      tempBackupPath = backupHistory.backupPath;

      final backupFile = File(backupHistory.backupPath);
      if (!await backupFile.exists()) {
        final errorMessage =
            'Arquivo de backup não existe: ${backupHistory.backupPath}';
        LoggerService.error(errorMessage);
        final finishedAt = DateTime.now();
        final failedHistory = backupHistory.copyWith(
          status: BackupStatus.error,
          errorMessage: errorMessage,
          finishedAt: finishedAt,
          durationSeconds: finishedAt
              .difference(backupHistory.startedAt)
              .inSeconds,
        );
        await _backupHistoryRepository.update(failedHistory);

        try {
          final progressProvider = getIt<BackupProgressProvider>();
          progressProvider.failBackup(errorMessage);
        } catch (_) {
          // Ignorar se não estiver disponível
        }

        return rd.Failure(BackupFailure(message: errorMessage));
      }

      final hasDestinations = destinations.isNotEmpty;

      if (hasDestinations) {
        try {
          final progressProvider = getIt<BackupProgressProvider>();
          progressProvider.updateProgress(
            step: BackupStep.uploading,
            message: 'Enviando para destinos...',
            progress: 0.85,
          );
        } catch (_) {
          // Ignorar se não estiver disponível
        }
      }

      final List<String> uploadErrors = [];
      bool hasCriticalUploadError = false;

      final totalDestinations = destinations.length;

      for (int index = 0; index < destinations.length; index++) {
        final destination = destinations[index];

        if (!await backupFile.exists()) {
          final errorMessage =
              'Arquivo de backup foi deletado antes de enviar para ${destination.name}: ${backupHistory.backupPath}';
          uploadErrors.add(errorMessage);
          LoggerService.error(errorMessage);
          hasCriticalUploadError = true;
          continue;
        }

        try {
          final progressProvider = getIt<BackupProgressProvider>();
          final progress = 0.85 + (0.1 * (index + 1) / totalDestinations);
          progressProvider.updateProgress(
            step: BackupStep.uploading,
            message: 'Enviando para ${destination.name}...',
            progress: progress,
          );
        } catch (_) {
          // Ignorar se não estiver disponível
        }

        final sendResult = await _sendToDestination(
          sourceFilePath: backupHistory.backupPath,
          destination: destination,
        );

        sendResult.fold((_) {}, (failure) {
          final failureMessage = failure is Failure
              ? failure.message
              : failure.toString();
          final errorMessage =
              'Falha ao enviar para ${destination.name}: $failureMessage';
          uploadErrors.add(errorMessage);
          LoggerService.error(errorMessage, failure);
          hasCriticalUploadError = true;
        });
      }

      if (hasCriticalUploadError) {
        final errorMessage = uploadErrors.join('\n');
        final finishedAt = DateTime.now();
        final failedHistory = backupHistory.copyWith(
          status: BackupStatus.error,
          errorMessage:
              'Backup concluído na pasta temporária, mas falhou ao enviar para destinos:\n$errorMessage',
          finishedAt: finishedAt,
          durationSeconds: finishedAt
              .difference(backupHistory.startedAt)
              .inSeconds,
        );
        await _backupHistoryRepository.update(failedHistory);

        await _log(
          backupHistory.id,
          'error',
          'Falha ao enviar backup para destinos:\n$errorMessage',
        );

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
              'Falha ao enviar backup para destinos:\n$errorMessage',
        );
        LoggerService.error(
          'Backup marcado como erro devido a falhas no upload',
          failure,
        );

        try {
          final progressProvider = getIt<BackupProgressProvider>();
          progressProvider.failBackup(errorMessage);
        } catch (_) {
          // Ignorar se não estiver disponível
        }

        return rd.Failure(failure);
      }

      if (uploadErrors.isNotEmpty) {
        final warningMessage =
            'O backup foi concluído, mas houve avisos:\n\n'
            '${uploadErrors.join('\n')}';

        await _notificationService.sendWarning(
          databaseName: schedule.name,
          message: warningMessage,
        );
      }

      if (hasDestinations) {
        LoggerService.info(
          'Uploads para destinos concluídos, enviando notificação por e-mail',
        );
      }
      await _notificationService.notifyBackupComplete(backupHistory);

      try {
        final progressProvider = getIt<BackupProgressProvider>();
        progressProvider.completeBackup(
          message: 'Backup concluído com sucesso!',
        );
      } catch (_) {
        // Ignorar se não estiver disponível
      }

      if (shouldDeleteTempFile) {
        try {
          final entityType = FileSystemEntity.typeSync(tempBackupPath);

          switch (entityType) {
            case FileSystemEntityType.file:
              final tempFile = File(tempBackupPath);
              if (tempFile.existsSync()) {
                await tempFile.delete();
                LoggerService.info(
                  'Arquivo temporário deletado: $tempBackupPath',
                );
              }
              break;
            case FileSystemEntityType.directory:
              final tempDir = Directory(tempBackupPath);
              if (tempDir.existsSync()) {
                await tempDir.delete(recursive: true);
                LoggerService.info(
                  'Diretório temporário deletado: $tempBackupPath',
                );
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
      final licenseCheck = await _ensureDestinationFeatureAllowed(destination);
      if (licenseCheck.isError()) {
        final failure = licenseCheck.exceptionOrNull()!;
        LoggerService.warning(
          'Envio bloqueado por licença: ${destination.name}',
          failure,
        );
        return rd.Failure(failure);
      }

      final configJson = jsonDecode(destination.config) as Map<String, dynamic>;

      switch (destination.type) {
        case DestinationType.local:
          final config = local.LocalDestinationConfig(
            path: configJson['path'] as String,
            createSubfoldersByDate:
                configJson['createSubfoldersByDate'] as bool? ?? true,
            retentionDays: configJson['retentionDays'] as int? ?? 30,
          );

          if (config.path.isEmpty) {
            final errorMessage =
                'Caminho do destino local está vazio para o destino: ${destination.name}';
            LoggerService.error(errorMessage);
            return rd.Failure(ValidationFailure(message: errorMessage));
          }

          LoggerService.info(
            'Copiando backup para destino local: ${destination.name} (${config.path})',
          );

          final uploadResult = await _localDestinationService.upload(
            sourceFilePath: sourceFilePath,
            config: config,
          );

          return uploadResult.fold(
            (result) {
              LoggerService.info(
                'Upload local concluído com sucesso: ${result.destinationPath} '
                '(${_formatBytes(result.fileSize)} em ${result.duration.inSeconds}s)',
              );
              return rd.Success(());
            },
            (failure) {
              LoggerService.error(
                'Erro ao copiar backup para destino local ${destination.name}',
                failure,
              );
              return rd.Failure(failure);
            },
          );

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

        case DestinationType.dropbox:
          final config = dropbox.DropboxDestinationConfig(
            folderPath: configJson['folderPath'] as String? ?? '',
            folderName: configJson['folderName'] as String? ?? 'Backups',
          );
          final result = await _sendToDropbox.call(
            sourceFilePath: sourceFilePath,
            config: config,
          );
          return result.fold(
            (_) => rd.Success(()),
            (failure) => rd.Failure(failure),
          );

        case DestinationType.nextcloud:
          final config = NextcloudDestinationConfig.fromJson(configJson);
          final result = await _sendToNextcloud.call(
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
        final licenseCheck = await _ensureDestinationFeatureAllowed(
          destination,
        );
        if (licenseCheck.isError()) {
          LoggerService.info(
            'Limpeza ignorada por licença: ${destination.name} '
            '(${destination.type.name})',
          );
          continue;
        }

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
            cleanResult.fold((_) {}, (exception) async {
              LoggerService.error(
                'Erro ao limpar backups FTP em ${destination.name}',
                exception,
              );
              final failureMessage = exception is Failure
                  ? exception.message
                  : exception.toString();

              await _log(
                backupHistoryId,
                'error',
                'Erro ao limpar backups antigos no FTP ${destination.name}: $failureMessage',
              );

              await _notificationService.sendWarning(
                databaseName: destination.name,
                message:
                    'Erro ao limpar backups antigos no FTP ${destination.name}: $failureMessage',
              );
            });
            break;

          case DestinationType.googleDrive:
            final config = gd.GoogleDriveDestinationConfig(
              folderId: configJson['folderId'] as String,
              folderName: configJson['folderName'] as String? ?? 'Backups',
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final cleanResult = await _googleDriveDestinationService
                .cleanOldBackups(config: config);
            cleanResult.fold((_) {}, (exception) async {
              LoggerService.error(
                'Erro ao limpar backups Google Drive em ${destination.name}',
                exception,
              );
              final failureMessage = exception is Failure
                  ? exception.message
                  : exception.toString();

              await _log(
                backupHistoryId,
                'error',
                'Erro ao limpar backups antigos no Google Drive ${destination.name}: $failureMessage',
              );

              await _notificationService.sendWarning(
                databaseName: destination.name,
                message:
                    'Erro ao limpar backups antigos no Google Drive ${destination.name}: $failureMessage',
              );
            });
            break;

          case DestinationType.dropbox:
            final config = dropbox.DropboxDestinationConfig(
              folderPath: configJson['folderPath'] as String? ?? '',
              folderName: configJson['folderName'] as String? ?? 'Backups',
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final cleanResult = await _dropboxDestinationService
                .cleanOldBackups(config: config);
            cleanResult.fold((_) {}, (exception) async {
              LoggerService.error(
                'Erro ao limpar backups Dropbox em ${destination.name}',
                exception,
              );
              final failureMessage = exception is Failure
                  ? exception.message
                  : exception.toString();

              await _log(
                backupHistoryId,
                'error',
                'Erro ao limpar backups antigos no Dropbox ${destination.name}: $failureMessage',
              );

              await _notificationService.sendWarning(
                databaseName: destination.name,
                message:
                    'Erro ao limpar backups antigos no Dropbox ${destination.name}: $failureMessage',
              );
            });
            break;

          case DestinationType.nextcloud:
            final config = NextcloudDestinationConfig.fromJson(configJson);
            final cleanResult = await _nextcloudDestinationService
                .cleanOldBackups(config: config);
            cleanResult.fold((_) {}, (exception) async {
              LoggerService.error(
                'Erro ao limpar backups Nextcloud em ${destination.name}',
                exception,
              );
              final failureMessage = exception is Failure
                  ? exception.message
                  : exception.toString();

              await _log(
                backupHistoryId,
                'error',
                'Erro ao limpar backups antigos no Nextcloud ${destination.name}: $failureMessage',
              );

              await _notificationService.sendWarning(
                databaseName: destination.name,
                message:
                    'Erro ao limpar backups antigos no Nextcloud ${destination.name}: $failureMessage',
              );
            });
            break;
        }
      } catch (e, stackTrace) {
        LoggerService.error(
          'Erro ao limpar backups em ${destination.name}',
          e,
          stackTrace,
        );

        await _log(
          backupHistoryId,
          'error',
          'Erro ao limpar backups antigos em ${destination.name}: $e',
        );

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

  Future<rd.Result<void>> executeNow(String scheduleId) async {
    final result = await _scheduleRepository.getById(scheduleId);

    return result.fold(
      (schedule) async => await _executeScheduledBackup(schedule),
      (failure) => rd.Failure(failure),
    );
  }

  Future<rd.Result<void>> refreshSchedule(String scheduleId) async {
    final result = await _scheduleRepository.getById(scheduleId);

    return result.fold((schedule) async {
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
      final testFileName =
          '.backup_permission_test_${DateTime.now().millisecondsSinceEpoch}';
      final testFile = File(
        '${directory.path}${Platform.pathSeparator}$testFileName',
      );

      await testFile.writeAsString('test');

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
