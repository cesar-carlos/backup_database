import 'dart:convert';

import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/core/utils/circuit_breaker.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/retry_utils.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:backup_database/domain/services/i_dropbox_destination_service.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_dropbox.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_ftp.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_nextcloud.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class DestinationOrchestratorImpl implements IDestinationOrchestrator {
  const DestinationOrchestratorImpl({
    required ILocalDestinationService localDestinationService,
    required SendToFtp sendToFtp,
    required IGoogleDriveDestinationService googleDriveDestinationService,
    required SendToDropbox sendToDropbox,
    required SendToNextcloud sendToNextcloud,
    required ILicensePolicyService licensePolicyService,
    required CircuitBreakerRegistry circuitBreakerRegistry,
  }) : _localDestinationService = localDestinationService,
       _sendToFtp = sendToFtp,
       _googleDriveDestinationService = googleDriveDestinationService,
       _sendToDropbox = sendToDropbox,
       _sendToNextcloud = sendToNextcloud,
       _licensePolicyService = licensePolicyService,
       _circuitBreakerRegistry = circuitBreakerRegistry;

  final ILocalDestinationService _localDestinationService;
  final SendToFtp _sendToFtp;
  final IGoogleDriveDestinationService _googleDriveDestinationService;
  final SendToDropbox _sendToDropbox;
  final SendToNextcloud _sendToNextcloud;
  final ILicensePolicyService _licensePolicyService;
  final CircuitBreakerRegistry _circuitBreakerRegistry;

  static String _uploadStepLabel(BackupDestination destination) {
    switch (destination.type) {
      case DestinationType.local:
        return 'Copiando para pasta local: ${destination.name}';
      case DestinationType.ftp:
        return 'Enviando para FTP: ${destination.name}';
      case DestinationType.googleDrive:
        return 'Enviando para Google Drive: ${destination.name}';
      case DestinationType.dropbox:
        return 'Enviando para Dropbox: ${destination.name}';
      case DestinationType.nextcloud:
        return 'Enviando para Nextcloud: ${destination.name}';
    }
  }

  @override
  Future<rd.Result<void>> uploadToDestination({
    required String sourceFilePath,
    required BackupDestination destination,
    bool Function()? isCancelled,
    String? backupId,
    UploadProgressCallback? onProgress,
  }) async {
    try {
      if (isCancelled != null && isCancelled()) {
        return const rd.Failure(
          BackupFailure(
            message: 'Upload cancelado pelo usuário.',
            code: FailureCodes.uploadCancelled,
          ),
        );
      }

      final licenseCheck = await _licensePolicyService
          .validateDestinationCapabilities(destination);
      if (licenseCheck.isError()) {
        final failure = licenseCheck.exceptionOrNull()!;
        LoggerService.warning(
          'Envio bloqueado por licença: ${destination.name}',
          failure,
        );
        return rd.Failure(failure);
      }

      final defaultStep = _uploadStepLabel(destination);
      final wrappedOnProgress = onProgress != null
          ? (double p, [String? stepOverride]) {
              onProgress(p, stepOverride ?? defaultStep);
            }
          : null;

      final configJson = jsonDecode(destination.config) as Map<String, dynamic>;

      switch (destination.type) {
        case DestinationType.local:
          return await _uploadToLocal(
            sourceFilePath,
            destination,
            configJson,
            backupId,
            wrappedOnProgress,
          );

        case DestinationType.ftp:
          return await _uploadToFtp(
            sourceFilePath,
            destination,
            configJson,
            isCancelled,
            backupId,
            wrappedOnProgress,
          );

        case DestinationType.googleDrive:
          return await _uploadToGoogleDrive(
            sourceFilePath,
            destination,
            configJson,
            isCancelled,
            backupId,
            wrappedOnProgress,
          );

        case DestinationType.dropbox:
          return await _uploadToDropbox(
            sourceFilePath,
            destination,
            configJson,
            isCancelled,
            backupId,
            wrappedOnProgress,
          );

        case DestinationType.nextcloud:
          return await _uploadToNextcloud(
            sourceFilePath,
            destination,
            configJson,
            isCancelled,
            backupId,
            wrappedOnProgress,
          );
      }
    } on Object catch (e) {
      LoggerService.error('Erro ao enviar para ${destination.name}: $e', e);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao enviar para ${destination.name}: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<List<rd.Result<void>>> uploadToAllDestinations({
    required String sourceFilePath,
    required List<BackupDestination> destinations,
    bool Function()? isCancelled,
    String? backupId,
    UploadProgressCallback? onProgress,
  }) async {
    if (destinations.isEmpty) {
      return [];
    }

    const maxParallel = UploadParallelismConstants.maxParallelUploads;
    final results = List<rd.Result<void>>.filled(
      destinations.length,
      const rd.Success(()),
    );

    for (var i = 0; i < destinations.length; i += maxParallel) {
      if (isCancelled != null && isCancelled()) {
        for (var j = i; j < destinations.length; j++) {
          results[j] = const rd.Failure(
            BackupFailure(
              message: 'Upload cancelado pelo usuário.',
              code: FailureCodes.uploadCancelled,
            ),
          );
        }
        break;
      }

      final end = i + maxParallel < destinations.length
          ? i + maxParallel
          : destinations.length;
      final batch = destinations.sublist(i, end);

      final batchFutures = batch.asMap().entries.map(
        (entry) => uploadToDestination(
          sourceFilePath: sourceFilePath,
          destination: entry.value,
          isCancelled: isCancelled,
          backupId: backupId,
          onProgress: onProgress,
        ),
      );

      final batchResults = await Future.wait(batchFutures);
      for (var j = 0; j < batchResults.length; j++) {
        results[i + j] = batchResults[j];
      }
    }

    return results;
  }

  Future<rd.Result<void>> _uploadToLocal(
    String sourceFilePath,
    BackupDestination destination,
    Map<String, dynamic> configJson,
    String? backupId,
    UploadProgressCallback? onProgress,
  ) async {
    final config = LocalDestinationConfig(
      path: configJson['path'] as String,
      createSubfoldersByDate:
          configJson['createSubfoldersByDate'] as bool? ?? true,
      retentionDays: configJson['retentionDays'] as int? ?? 30,
    );

    if (config.path.isEmpty) {
      final errorMessage =
          'Caminho do destino local está vazio para o destino: '
          '${destination.name}';
      LoggerService.error(errorMessage);
      return rd.Failure(ValidationFailure(message: errorMessage));
    }

    LoggerService.info(
      'Copiando backup para destino local: ${destination.name} '
      '(${config.path})',
    );

    onProgress?.call(0, 'Preparando cópia para pasta local: ${destination.name}');

    final customFileName = backupId != null
        ? SybaseBackupPathSuffix.buildDestinationName(
            p.basename(sourceFilePath),
            backupId,
          )
        : null;

    final uploadResult = await _localDestinationService.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
      onProgress: onProgress,
    );

    return uploadResult.fold(
      (result) {
        LoggerService.info(
          'Upload local concluído com sucesso: '
          '${result.destinationPath} '
          '(${_formatBytes(result.fileSize)} em '
          '${result.duration.inSeconds}s)',
        );
        return const rd.Success(());
      },
      (failure) {
        LoggerService.error(
          'Erro ao copiar backup para destino local ${destination.name}',
          failure,
        );
        return rd.Failure(failure);
      },
    );
  }

  Future<rd.Result<void>> _uploadToFtp(
    String sourceFilePath,
    BackupDestination destination,
    Map<String, dynamic> configJson,
    bool Function()? isCancelled,
    String? backupId,
    UploadProgressCallback? onProgress,
  ) async {
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);
    if (!breaker.allowsRequest) {
      LoggerService.warning(
        'Circuit breaker aberto para ${destination.name}, pulando upload FTP',
      );
      return rd.Failure(
        BackupFailure(
          message:
              'Destino ${destination.name} temporariamente indisponível '
              '(circuit breaker aberto). Tente novamente mais tarde.',
          code: FailureCodes.circuitBreakerOpen,
        ),
      );
    }

    final config = FtpDestinationConfig(
      host: configJson['host'] as String,
      port: configJson['port'] as int? ?? 21,
      username: configJson['username'] as String,
      password: configJson['password'] as String,
      remotePath: configJson['remotePath'] as String? ?? '/',
      useFtps: configJson['useFtps'] as bool? ?? false,
      enableResume: configJson['enableResume'] as bool? ?? true,
      keepPartOnCancel: configJson['keepPartOnCancel'] as bool? ?? true,
      maxAttempts: configJson['maxAttempts'] as int?,
      whenResumeNotSupported: _parseWhenResumeNotSupported(
        configJson['whenResumeNotSupported'] as String?,
      ),
      enableVerboseLog: configJson['enableVerboseLog'] as bool? ?? false,
      connectionTimeoutSeconds:
          configJson['connectionTimeoutSeconds'] as int?,
      uploadTimeoutMinutes: configJson['uploadTimeoutMinutes'] as int?,
    );

    LoggerService.info(
      'Enviando backup para FTP: ${destination.name} (${config.host})',
    );

    final uploadResult = await executeResultWithRetry<FtpUploadResult>(
      maxAttempts: config.effectiveMaxAttempts,
      operation: () async {
        if (isCancelled != null && isCancelled()) {
          return const rd.Failure(
            BackupFailure(
              message: 'Upload cancelado pelo usuário.',
              code: FailureCodes.uploadCancelled,
            ),
          );
        }
        final customFileName = backupId != null
            ? SybaseBackupPathSuffix.buildDestinationName(
                p.basename(sourceFilePath),
                backupId,
              )
            : null;
        return _sendToFtp.call(
          sourceFilePath: sourceFilePath,
          config: config,
          customFileName: customFileName,
          isCancelled: isCancelled,
          onProgress: onProgress,
          runId: LogContext.runId,
          destinationId: destination.id,
        );
      },
      operationName: 'Upload FTP ${destination.name}',
    );

    return uploadResult.fold(
      (FtpUploadResult result) {
        breaker.recordSuccess();
        LoggerService.info(
          'Upload FTP concluído com sucesso: ${result.remotePath} '
          '(${_formatBytes(result.fileSize)} em '
          '${result.duration.inSeconds}s)',
        );
        return const rd.Success(());
      },
      (failure) {
        breaker.recordFailure(failure);
        LoggerService.error(
          'Erro ao enviar backup para FTP ${destination.name}',
          failure,
        );
        return rd.Failure(failure);
      },
    );
  }

  Future<rd.Result<void>> _uploadToGoogleDrive(
    String sourceFilePath,
    BackupDestination destination,
    Map<String, dynamic> configJson,
    bool Function()? isCancelled,
    String? backupId,
    UploadProgressCallback? onProgress,
  ) async {
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);
    if (!breaker.allowsRequest) {
      LoggerService.warning(
        'Circuit breaker aberto para ${destination.name}, pulando upload',
      );
      return rd.Failure(
        BackupFailure(
          message:
              'Destino ${destination.name} temporariamente indisponível '
              '(circuit breaker aberto). Tente novamente mais tarde.',
          code: FailureCodes.circuitBreakerOpen,
        ),
      );
    }

    final config = GoogleDriveDestinationConfig(
      folderId: configJson['folderId'] as String,
      folderName: configJson['folderName'] as String? ?? 'Backups',
      accessToken: configJson['accessToken'] as String? ?? '',
      refreshToken: configJson['refreshToken'] as String? ?? '',
    );
    final result = await executeResultWithRetry<GoogleDriveUploadResult>(
      operation: () async {
        if (isCancelled != null && isCancelled()) {
          return const rd.Failure(
            BackupFailure(
              message: 'Upload cancelado pelo usuário.',
              code: FailureCodes.uploadCancelled,
            ),
          );
        }
        final customFileName = backupId != null
            ? SybaseBackupPathSuffix.buildDestinationName(
                p.basename(sourceFilePath),
                backupId,
              )
            : null;
        return _googleDriveDestinationService.upload(
          sourceFilePath: sourceFilePath,
          config: config,
          customFileName: customFileName,
          onProgress: onProgress,
        );
      },
      operationName: 'Upload Google Drive ${destination.name}',
    );
    return result.fold(
      (_) {
        breaker.recordSuccess();
        return const rd.Success(());
      },
      (failure) {
        breaker.recordFailure(failure);
        return rd.Failure(failure);
      },
    );
  }

  Future<rd.Result<void>> _uploadToDropbox(
    String sourceFilePath,
    BackupDestination destination,
    Map<String, dynamic> configJson,
    bool Function()? isCancelled,
    String? backupId,
    UploadProgressCallback? onProgress,
  ) async {
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);
    if (!breaker.allowsRequest) {
      LoggerService.warning(
        'Circuit breaker aberto para ${destination.name}, pulando upload',
      );
      return rd.Failure(
        BackupFailure(
          message:
              'Destino ${destination.name} temporariamente indisponível '
              '(circuit breaker aberto). Tente novamente mais tarde.',
          code: FailureCodes.circuitBreakerOpen,
        ),
      );
    }

    final config = DropboxDestinationConfig(
      folderPath: configJson['folderPath'] as String? ?? '',
      folderName: configJson['folderName'] as String? ?? 'Backups',
    );
    final result = await executeResultWithRetry<DropboxUploadResult>(
      operation: () async {
        if (isCancelled != null && isCancelled()) {
          return const rd.Failure(
            BackupFailure(
              message: 'Upload cancelado pelo usuário.',
              code: FailureCodes.uploadCancelled,
            ),
          );
        }
        final customFileName = backupId != null
            ? SybaseBackupPathSuffix.buildDestinationName(
                p.basename(sourceFilePath),
                backupId,
              )
            : null;
        return _sendToDropbox.call(
          sourceFilePath: sourceFilePath,
          config: config,
          customFileName: customFileName,
          onProgress: onProgress,
        );
      },
      operationName: 'Upload Dropbox ${destination.name}',
    );
    return result.fold(
      (_) {
        breaker.recordSuccess();
        return const rd.Success(());
      },
      (failure) {
        breaker.recordFailure(failure);
        return rd.Failure(failure);
      },
    );
  }

  Future<rd.Result<void>> _uploadToNextcloud(
    String sourceFilePath,
    BackupDestination destination,
    Map<String, dynamic> configJson,
    bool Function()? isCancelled,
    String? backupId,
    UploadProgressCallback? onProgress,
  ) async {
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);
    if (!breaker.allowsRequest) {
      LoggerService.warning(
        'Circuit breaker aberto para ${destination.name}, pulando upload',
      );
      return rd.Failure(
        BackupFailure(
          message:
              'Destino ${destination.name} temporariamente indisponível '
              '(circuit breaker aberto). Tente novamente mais tarde.',
          code: FailureCodes.circuitBreakerOpen,
        ),
      );
    }

    final config = NextcloudDestinationConfig.fromJson(configJson);
    final result = await executeResultWithRetry<NextcloudUploadResult>(
      operation: () async {
        if (isCancelled != null && isCancelled()) {
          return const rd.Failure(
            BackupFailure(
              message: 'Upload cancelado pelo usuário.',
              code: FailureCodes.uploadCancelled,
            ),
          );
        }
        final customFileName = backupId != null
            ? SybaseBackupPathSuffix.buildDestinationName(
                p.basename(sourceFilePath),
                backupId,
              )
            : null;
        return _sendToNextcloud.call(
          sourceFilePath: sourceFilePath,
          config: config,
          customFileName: customFileName,
          onProgress: onProgress,
        );
      },
      operationName: 'Upload Nextcloud ${destination.name}',
    );
    return result.fold(
      (_) {
        breaker.recordSuccess();
        return const rd.Success(());
      },
      (failure) {
        breaker.recordFailure(failure);
        return rd.Failure(failure);
      },
    );
  }

  static FtpWhenResumeNotSupported _parseWhenResumeNotSupported(
    String? value,
  ) {
    if (value == null) return FtpWhenResumeNotSupported.fallback;
    return FtpWhenResumeNotSupported.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FtpWhenResumeNotSupported.fallback,
    );
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
}
