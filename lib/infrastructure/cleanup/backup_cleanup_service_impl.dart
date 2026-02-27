import 'dart:convert';

import 'package:backup_database/core/constants/log_step_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/services/i_backup_cleanup_service.dart';
import 'package:backup_database/domain/services/i_dropbox_destination_service.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupCleanupServiceImpl implements IBackupCleanupService {
  const BackupCleanupServiceImpl({
    required ILocalDestinationService localDestinationService,
    required IFtpService ftpDestinationService,
    required IGoogleDriveDestinationService googleDriveDestinationService,
    required IDropboxDestinationService dropboxDestinationService,
    required INextcloudDestinationService nextcloudDestinationService,
    required ILicensePolicyService licensePolicyService,
    required INotificationService notificationService,
    required IBackupLogRepository backupLogRepository,
  }) : _localDestinationService = localDestinationService,
       _ftpDestinationService = ftpDestinationService,
       _googleDriveDestinationService = googleDriveDestinationService,
       _dropboxDestinationService = dropboxDestinationService,
       _nextcloudDestinationService = nextcloudDestinationService,
       _licensePolicyService = licensePolicyService,
       _notificationService = notificationService,
       _backupLogRepository = backupLogRepository;

  final ILocalDestinationService _localDestinationService;
  final IFtpService _ftpDestinationService;
  final IGoogleDriveDestinationService _googleDriveDestinationService;
  final IDropboxDestinationService _dropboxDestinationService;
  final INextcloudDestinationService _nextcloudDestinationService;
  final ILicensePolicyService _licensePolicyService;
  final INotificationService _notificationService;
  final IBackupLogRepository _backupLogRepository;

  @override
  Future<rd.Result<void>> cleanOldBackups({
    required List<BackupDestination> destinations,
    required String backupHistoryId,
  }) async {
    try {
      for (final destination in destinations) {
        await _cleanDestination(destination, backupHistoryId);
      }
      return const rd.Success(());
    } on Object catch (e) {
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao limpar backups: $e',
          code: FailureCodes.cleanupFailed,
          originalError: e,
        ),
      );
    }
  }

  Future<void> _cleanDestination(
    BackupDestination destination,
    String backupHistoryId,
  ) async {
    try {
      final licenseCheck =
          await _licensePolicyService.validateDestinationCapabilities(destination);
      if (licenseCheck.isError()) {
        LoggerService.info(
          'Limpeza ignorada por licença: ${destination.name} '
          '(${destination.type.name})',
        );
        return;
      }

      final configJson = jsonDecode(destination.config) as Map<String, dynamic>;

      switch (destination.type) {
        case DestinationType.local:
          await _cleanLocal(destination, configJson);

        case DestinationType.ftp:
          await _cleanFtp(destination, configJson, backupHistoryId);

        case DestinationType.googleDrive:
          await _cleanGoogleDrive(destination, configJson, backupHistoryId);

        case DestinationType.dropbox:
          await _cleanDropbox(destination, configJson, backupHistoryId);

        case DestinationType.nextcloud:
          await _cleanNextcloud(destination, configJson, backupHistoryId);
      }
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao limpar backups em ${destination.name}',
        e,
        stackTrace,
      );

      await _log(
        backupHistoryId,
        'error',
        'Erro ao limpar backups antigos em ${destination.name}: $e',
        step: LogStepConstants.cleanupError(destination.id),
      );

      await _notificationService.sendWarning(
        databaseName: destination.name,
        message: 'Erro ao limpar backups antigos em ${destination.name}: $e',
      );
    }
  }

  Future<void> _cleanLocal(
    BackupDestination destination,
    Map<String, dynamic> configJson,
  ) async {
    final config = LocalDestinationConfig(
      path: configJson['path'] as String,
      retentionDays: configJson['retentionDays'] as int? ?? 30,
    );
    await _localDestinationService.cleanOldBackups(config: config);
  }

  Future<void> _cleanFtp(
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String backupHistoryId,
  ) async {
    final config = FtpDestinationConfig(
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
        'Erro ao limpar backups antigos no FTP ${destination.name}: '
            '$failureMessage',
        step: LogStepConstants.cleanupError(destination.id),
      );

      await _notificationService.sendWarning(
        databaseName: destination.name,
        message:
            'Erro ao limpar backups antigos no FTP '
            '${destination.name}: $failureMessage',
      );
    });
  }

  Future<void> _cleanGoogleDrive(
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String backupHistoryId,
  ) async {
    final config = GoogleDriveDestinationConfig(
      folderId: configJson['folderId'] as String,
      folderName: configJson['folderName'] as String? ?? 'Backups',
      accessToken: configJson['accessToken'] as String? ?? '',
      refreshToken: configJson['refreshToken'] as String? ?? '',
      retentionDays: configJson['retentionDays'] as int? ?? 30,
    );
    final cleanResult = await _googleDriveDestinationService.cleanOldBackups(
      config: config,
    );
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
        'Erro ao limpar backups antigos no Google Drive '
            '${destination.name}: $failureMessage',
        step: LogStepConstants.cleanupError(destination.id),
      );

      await _notificationService.sendWarning(
        databaseName: destination.name,
        message:
            'Erro ao limpar backups antigos no Google Drive '
            '${destination.name}: $failureMessage',
      );
    });
  }

  Future<void> _cleanDropbox(
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String backupHistoryId,
  ) async {
    final config = DropboxDestinationConfig(
      folderPath: configJson['folderPath'] as String? ?? '',
      folderName: configJson['folderName'] as String? ?? 'Backups',
      retentionDays: configJson['retentionDays'] as int? ?? 30,
    );
    final cleanResult = await _dropboxDestinationService.cleanOldBackups(
      config: config,
    );
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
        'Erro ao limpar backups antigos no Dropbox '
            '${destination.name}: $failureMessage',
        step: LogStepConstants.cleanupError(destination.id),
      );

      await _notificationService.sendWarning(
        databaseName: destination.name,
        message:
            'Erro ao limpar backups antigos no Dropbox '
            '${destination.name}: $failureMessage',
      );
    });
  }

  Future<void> _cleanNextcloud(
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String backupHistoryId,
  ) async {
    final config = NextcloudDestinationConfig.fromJson(configJson);
    final cleanResult = await _nextcloudDestinationService.cleanOldBackups(
      config: config,
    );
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
        'Erro ao limpar backups antigos no Nextcloud '
            '${destination.name}: $failureMessage',
        step: LogStepConstants.cleanupError(destination.id),
      );

      await _notificationService.sendWarning(
        databaseName: destination.name,
        message:
            'Erro ao limpar backups antigos no Nextcloud '
            '${destination.name}: $failureMessage',
      );
    });
  }

  Future<void> _log(
    String historyId,
    String levelStr,
    String message, {
    String? step,
  }) async {
    try {
      final level = _logLevelFromString(levelStr);
      if (step != null) {
        final result = await _backupLogRepository.createIdempotent(
          backupHistoryId: historyId,
          step: step,
          level: level,
          category: LogCategory.execution,
          message: message,
        );
        result.fold(
          (_) {},
          (e) => LoggerService.warning('Erro ao gravar log idempotente: $e'),
        );
        return;
      }

      final log = BackupLog(
        backupHistoryId: historyId,
        level: level,
        category: LogCategory.execution,
        message: message,
      );
      await _backupLogRepository.create(log);
    } on Object catch (e) {
      LoggerService.warning('Erro ao gravar log no banco: $e');
    }
  }

  LogLevel _logLevelFromString(String levelStr) {
    switch (levelStr) {
      case 'info':
        return LogLevel.info;
      case 'warning':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }
}
