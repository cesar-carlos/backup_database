import 'dart:convert';

import 'package:backup_database/core/constants/log_step_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/services/i_backup_cleanup_service.dart';
import 'package:backup_database/domain/services/i_dropbox_destination_service.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/use_cases/backup/compute_sybase_retention_protected_ids.dart';
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
    required IBackupHistoryRepository backupHistoryRepository,
  }) : _localDestinationService = localDestinationService,
       _ftpDestinationService = ftpDestinationService,
       _googleDriveDestinationService = googleDriveDestinationService,
       _dropboxDestinationService = dropboxDestinationService,
       _nextcloudDestinationService = nextcloudDestinationService,
       _licensePolicyService = licensePolicyService,
       _notificationService = notificationService,
       _backupLogRepository = backupLogRepository,
       _backupHistoryRepository = backupHistoryRepository;

  final ILocalDestinationService _localDestinationService;
  final IFtpService _ftpDestinationService;
  final IGoogleDriveDestinationService _googleDriveDestinationService;
  final IDropboxDestinationService _dropboxDestinationService;
  final INextcloudDestinationService _nextcloudDestinationService;
  final ILicensePolicyService _licensePolicyService;
  final INotificationService _notificationService;
  final IBackupLogRepository _backupLogRepository;
  final IBackupHistoryRepository _backupHistoryRepository;

  static const _computeRetention = ComputeSybaseRetentionProtectedIds();

  @override
  Future<rd.Result<void>> cleanOldBackups({
    required List<BackupDestination> destinations,
    required String backupHistoryId,
    Schedule? schedule,
  }) async {
    try {
      final protectedShortIds = await _computeProtectedShortIds(
        schedule,
        destinations,
      );

      for (final destination in destinations) {
        await _cleanDestination(
          destination,
          backupHistoryId,
          protectedShortIds,
        );
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

  Future<Set<String>> _computeProtectedShortIds(
    Schedule? schedule,
    List<BackupDestination> destinations,
  ) async {
    if (schedule == null || schedule.databaseType != DatabaseType.sybase) {
      return const {};
    }

    final historiesResult = await _backupHistoryRepository.getBySchedule(
      schedule.id,
    );
    if (historiesResult.isError()) return const {};

    final histories = historiesResult.getOrNull() ?? [];
    if (histories.isEmpty) return const {};

    var maxRetention = 30;
    for (final d in destinations) {
      try {
        final config = jsonDecode(d.config) as Map<String, dynamic>;
        final days = config['retentionDays'] as int? ?? 30;
        if (days > maxRetention) maxRetention = days;
      } on Object {
        // ignore invalid configs
      }
    }

    final protected = _computeRetention(
      histories: histories,
      retentionDays: maxRetention,
    );
    return SybaseBackupPathSuffix.toShortIds(protected);
  }

  Future<void> _cleanDestination(
    BackupDestination destination,
    String backupHistoryId,
    Set<String> protectedShortIds,
  ) async {
    try {
      final licenseCheck = await _licensePolicyService
          .validateDestinationCapabilities(destination);
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
          await _cleanLocal(
            destination,
            configJson,
            protectedShortIds,
          );

        case DestinationType.ftp:
          await _cleanFtp(
            destination,
            configJson,
            backupHistoryId,
            protectedShortIds,
          );

        case DestinationType.googleDrive:
          await _cleanGoogleDrive(
            destination,
            configJson,
            backupHistoryId,
            protectedShortIds,
          );

        case DestinationType.dropbox:
          await _cleanDropbox(
            destination,
            configJson,
            backupHistoryId,
            protectedShortIds,
          );

        case DestinationType.nextcloud:
          await _cleanNextcloud(
            destination,
            configJson,
            backupHistoryId,
            protectedShortIds,
          );
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
    Set<String> protectedShortIds,
  ) async {
    final config = LocalDestinationConfig(
      path: configJson['path'] as String,
      retentionDays: configJson['retentionDays'] as int? ?? 30,
      protectedBackupIdShortPrefixes: protectedShortIds,
    );
    await _localDestinationService.cleanOldBackups(config: config);
  }

  Future<void> _cleanFtp(
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String backupHistoryId,
    Set<String> protectedShortIds,
  ) async {
    final config = FtpDestinationConfig.fromJson(configJson);
    final configWithProtected = FtpDestinationConfig(
      host: config.host,
      port: config.port,
      username: config.username,
      password: config.password,
      remotePath: config.remotePath,
      useFtps: config.useFtps,
      retentionDays: config.retentionDays,
      enableResume: config.enableResume,
      keepPartOnCancel: config.keepPartOnCancel,
      maxAttempts: config.maxAttempts,
      whenResumeNotSupported: config.whenResumeNotSupported,
      enableVerboseLog: config.enableVerboseLog,
      connectionTimeoutSeconds: config.connectionTimeoutSeconds,
      uploadTimeoutMinutes: config.uploadTimeoutMinutes,
      protectedBackupIdShortPrefixes: protectedShortIds,
    );
    await _runRemoteCleanup(
      label: 'FTP',
      destination: destination,
      backupHistoryId: backupHistoryId,
      clean: () =>
          _ftpDestinationService.cleanOldBackups(config: configWithProtected),
    );
  }

  Future<void> _cleanGoogleDrive(
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String backupHistoryId,
    Set<String> protectedShortIds,
  ) async {
    final config = GoogleDriveDestinationConfig(
      folderId: configJson['folderId'] as String,
      folderName: configJson['folderName'] as String? ?? 'Backups',
      accessToken: configJson['accessToken'] as String? ?? '',
      refreshToken: configJson['refreshToken'] as String? ?? '',
      retentionDays: configJson['retentionDays'] as int? ?? 30,
      protectedBackupIdShortPrefixes: protectedShortIds,
    );
    await _runRemoteCleanup(
      label: 'Google Drive',
      destination: destination,
      backupHistoryId: backupHistoryId,
      clean: () =>
          _googleDriveDestinationService.cleanOldBackups(config: config),
    );
  }

  Future<void> _cleanDropbox(
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String backupHistoryId,
    Set<String> protectedShortIds,
  ) async {
    final config = DropboxDestinationConfig(
      folderPath: configJson['folderPath'] as String? ?? '',
      folderName: configJson['folderName'] as String? ?? 'Backups',
      retentionDays: configJson['retentionDays'] as int? ?? 30,
      protectedBackupIdShortPrefixes: protectedShortIds,
    );
    await _runRemoteCleanup(
      label: 'Dropbox',
      destination: destination,
      backupHistoryId: backupHistoryId,
      clean: () => _dropboxDestinationService.cleanOldBackups(config: config),
    );
  }

  Future<void> _cleanNextcloud(
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String backupHistoryId,
    Set<String> protectedShortIds,
  ) async {
    final baseConfig = NextcloudDestinationConfig.fromJson(configJson);
    final config = NextcloudDestinationConfig(
      serverUrl: baseConfig.serverUrl,
      username: baseConfig.username,
      appPassword: baseConfig.appPassword,
      authMode: baseConfig.authMode,
      remotePath: baseConfig.remotePath,
      folderName: baseConfig.folderName,
      allowInvalidCertificates: baseConfig.allowInvalidCertificates,
      retentionDays: baseConfig.retentionDays,
      protectedBackupIdShortPrefixes: protectedShortIds,
    );
    await _runRemoteCleanup(
      label: 'Nextcloud',
      destination: destination,
      backupHistoryId: backupHistoryId,
      clean: () =>
          _nextcloudDestinationService.cleanOldBackups(config: config),
    );
  }

  /// Executa a função `clean` para uma destination remota e centraliza:
  ///  - log estruturado em caso de falha;
  ///  - registro de erro idempotente no histórico do backup;
  ///  - envio de notificação de warning.
  ///
  /// Substitui as quatro implementações praticamente idênticas que existiam
  /// para FTP, Google Drive, Dropbox e Nextcloud, eliminando ~120 linhas
  /// duplicadas e o risco de evoluir o tratamento de erro em apenas um
  /// destino.
  Future<void> _runRemoteCleanup({
    required String label,
    required BackupDestination destination,
    required String backupHistoryId,
    required Future<rd.Result<dynamic>> Function() clean,
  }) async {
    final result = await clean();
    await result.fold((_) async {}, (exception) async {
      LoggerService.error(
        'Erro ao limpar backups $label em ${destination.name}',
        exception,
      );
      final failureMessage = exception is Failure
          ? exception.message
          : exception.toString();

      await _log(
        backupHistoryId,
        'error',
        'Erro ao limpar backups antigos no $label '
            '${destination.name}: $failureMessage',
        step: LogStepConstants.cleanupError(destination.id),
      );

      await _notificationService.sendWarning(
        databaseName: destination.name,
        message:
            'Erro ao limpar backups antigos no $label '
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
      final level = LogLevel.fromString(levelStr);
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
}
