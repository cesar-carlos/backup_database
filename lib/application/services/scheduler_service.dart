import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;

import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/backup_destination.dart';
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
    required BackupOrchestratorService backupOrchestratorService,
    required local.LocalDestinationService localDestinationService,
    required SendToFtp sendToFtp,
    required ftp.FtpDestinationService ftpDestinationService,
    required gd.GoogleDriveDestinationService googleDriveDestinationService,
    required NotificationService notificationService,
  })  : _scheduleRepository = scheduleRepository,
        _destinationRepository = destinationRepository,
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
        LoggerService.error(
          'Erro ao atualizar schedules: ${failure.message}',
        );
      },
    );
  }

  /// Verifica schedules pendentes
  Future<void> _checkSchedules() async {
    if (!_isRunning) return;

    final result = await _scheduleRepository.getEnabled();

    result.fold(
      (schedules) async {
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
            unawaited(_executeScheduledBackup(schedule).then((_) {
              _executingSchedules.remove(schedule.id);
            }).catchError((error) {
              _executingSchedules.remove(schedule.id);
            }));
          }
        }
      },
      (failure) => null,
    );
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
          path: (jsonDecode(localDestination.config)
              as Map<String, dynamic>)['path'] as String,
          createSubfoldersByDate:
              (jsonDecode(localDestination.config) as Map<String, dynamic>)[
                      'createSubfoldersByDate'] as bool? ??
                  true,
          retentionDays: (jsonDecode(localDestination.config)
                  as Map<String, dynamic>)['retentionDays'] as int? ??
              30,
        );
        outputDirectory = localConfig.path;
      } else {
        // Se não houver destino local, usar pasta temporária acessível pelo SQL Server
        // O SQL Server precisa de permissão para escrever, então usamos uma pasta no sistema
        // ou criamos uma pasta específica para backups temporários
        final systemTemp = Platform.environment['TEMP'] ?? 
                          Platform.environment['TMP'] ?? 
                          'C:\\Temp';
        
        // Criar pasta específica para backups temporários
        final backupTempDir = Directory('$systemTemp\\BackupDatabase');
        if (!await backupTempDir.exists()) {
          await backupTempDir.create(recursive: true);
        }
        
        outputDirectory = backupTempDir.path;
        shouldDeleteTempFile = true;
        LoggerService.info(
          'Nenhum destino local configurado, usando pasta temporária para SQL Server: $outputDirectory',
        );
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
        (d) => d.type == DestinationType.ftp || d.type == DestinationType.googleDrive,
      );

      // Enviar para destinos configurados
      for (final destination in destinations) {
        if (destination.type == DestinationType.local) {
          // Destino local já foi salvo durante o backup
          continue;
        }

        await _sendToDestination(
          sourceFilePath: backupHistory.backupPath,
          destination: destination,
        );
      }

      // Enviar notificação por e-mail apenas após upload para destinos remotos
      // Se não houver destinos remotos, enviar imediatamente
      if (hasRemoteDestinations) {
        LoggerService.info('Uploads para destinos remotos concluídos, enviando notificação por e-mail');
      }
      await _notificationService.notifyBackupComplete(backupHistory);

      // Se usamos pasta temporária e não há destino local, deletar arquivo após enviar
      if (shouldDeleteTempFile) {
        try {
          final tempFile = File(tempBackupPath);
          if (tempFile.existsSync()) {
            await tempFile.delete();
            LoggerService.info('Arquivo temporário deletado: $tempBackupPath');
          }
        } catch (e) {
          LoggerService.warning(
            'Erro ao deletar arquivo temporário: $e',
          );
        }
      }

      // Atualizar próxima execução
      final nextRunAt = _calculator.getNextRunTime(schedule);
      final updatedSchedule = schedule.copyWith(
        lastRunAt: DateTime.now(),
        nextRunAt: nextRunAt,
      );
      await _scheduleRepository.update(updatedSchedule);
      
      LoggerService.info(
        'Próxima execução de ${schedule.name} agendada para: $nextRunAt',
      );

      // Limpar backups antigos
      await _cleanOldBackups(destinations);

      LoggerService.info('Backup agendado concluído: ${schedule.name}');
      return rd.Success(());
    } catch (e, stackTrace) {
      LoggerService.error('Erro no backup agendado', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro no backup agendado: $e',
          originalError: e,
        ),
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

  Future<void> _sendToDestination({
    required String sourceFilePath,
    required BackupDestination destination,
  }) async {
    try {
      final configJson =
          jsonDecode(destination.config) as Map<String, dynamic>;

      switch (destination.type) {
        case DestinationType.local:
          // Já foi salvo localmente
          break;

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
          
          uploadResult.fold(
            (result) {
              LoggerService.info(
                'Upload FTP concluído com sucesso: ${result.remotePath} '
                '(${_formatBytes(result.fileSize)} em ${result.duration.inSeconds}s)',
              );
            },
            (failure) {
              LoggerService.error(
                'Erro ao enviar backup para FTP ${destination.name}',
                failure,
              );
              throw failure;
            },
          );
          break;

        case DestinationType.googleDrive:
          final config = gd.GoogleDriveDestinationConfig(
            folderId: configJson['folderId'] as String,
            folderName: configJson['folderName'] as String? ?? 'Backups',
          );
          await _googleDriveDestinationService.upload(
            sourceFilePath: sourceFilePath,
            config: config,
          );
          break;
      }
    } catch (e) {
      LoggerService.warning('Erro ao enviar para ${destination.name}: $e');
    }
  }

  Future<void> _cleanOldBackups(List<BackupDestination> destinations) async {
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
            await _ftpDestinationService.cleanOldBackups(config: config);
            break;

          case DestinationType.googleDrive:
            final config = gd.GoogleDriveDestinationConfig(
              folderId: configJson['folderId'] as String,
              folderName: configJson['folderName'] as String? ?? 'Backups',
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            await _googleDriveDestinationService.cleanOldBackups(
              config: config,
            );
            break;
        }
      } catch (e) {
        LoggerService.warning(
          'Erro ao limpar backups em ${destination.name}: $e',
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

    return result.fold(
      (schedule) async {
        // Calcular e atualizar próxima execução
        final nextRunAt = _calculator.getNextRunTime(schedule);
        if (nextRunAt != null) {
          await _scheduleRepository.update(
            schedule.copyWith(nextRunAt: nextRunAt),
          );
        }
        return rd.Success(());
      },
      (failure) => rd.Failure(failure),
    );
  }

  bool get isRunning => _isRunning;
}

