import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/circuit_breaker.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/retry_utils.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
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
import 'package:backup_database/domain/use_cases/destinations/send_to_google_drive.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_nextcloud.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class DestinationOrchestratorImpl implements IDestinationOrchestrator {
  const DestinationOrchestratorImpl({
    required ILocalDestinationService localDestinationService,
    required SendToFtp sendToFtp,
    required SendToGoogleDrive sendToGoogleDrive,
    required SendToDropbox sendToDropbox,
    required SendToNextcloud sendToNextcloud,
    required ILicensePolicyService licensePolicyService,
    required CircuitBreakerRegistry circuitBreakerRegistry,
  }) : _localDestinationService = localDestinationService,
       _sendToFtp = sendToFtp,
       _sendToGoogleDrive = sendToGoogleDrive,
       _sendToDropbox = sendToDropbox,
       _sendToNextcloud = sendToNextcloud,
       _licensePolicyService = licensePolicyService,
       _circuitBreakerRegistry = circuitBreakerRegistry;

  final ILocalDestinationService _localDestinationService;
  final SendToFtp _sendToFtp;
  final SendToGoogleDrive _sendToGoogleDrive;
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
        return UploadCancellation.cancelledResult();
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

      final configResult = _parseConfigJson(destination);
      if (configResult.isError()) {
        return rd.Failure(configResult.exceptionOrNull()!);
      }
      final configJson = configResult.getOrNull()!;

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

    final maxParallel = _resolveMaxParallelUploads();
    final results = List<rd.Result<void>>.filled(
      destinations.length,
      const rd.Success(()),
    );

    for (var i = 0; i < destinations.length; i += maxParallel) {
      if (isCancelled != null && isCancelled()) {
        for (var j = i; j < destinations.length; j++) {
          results[j] = UploadCancellation.cancelledResult();
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

    onProgress?.call(
      0,
      'Preparando cópia para pasta local: ${destination.name}',
    );

    final uploadResult = await _localDestinationService.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: _buildCustomFileName(sourceFilePath, backupId),
      onProgress: onProgress,
    );

    return uploadResult.fold(
      (result) {
        LoggerService.info(
          'Upload local concluído com sucesso: '
          '${result.destinationPath} '
          '(${ByteFormat.format(result.fileSize)} em '
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
    final breakerFailure = _circuitBreakerGuard(destination);
    if (breakerFailure != null) return breakerFailure;
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);

    final config = FtpDestinationConfig.fromJson(configJson);

    LoggerService.info(
      'Enviando backup para FTP: ${destination.name} (${config.host})',
    );

    final uploadResult = await executeResultWithRetry<FtpUploadResult>(
      maxAttempts: config.effectiveMaxAttempts,
      isCancelled: isCancelled,
      operation: () async {
        if (isCancelled != null && isCancelled()) {
          return _cancelledFailure();
        }
        return _sendToFtp.call(
          sourceFilePath: sourceFilePath,
          config: config,
          customFileName: _buildCustomFileName(sourceFilePath, backupId),
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
          '(${ByteFormat.format(result.fileSize)} em '
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
    final breakerFailure = _circuitBreakerGuard(destination);
    if (breakerFailure != null) return breakerFailure;
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);

    final config = GoogleDriveDestinationConfig.fromJson(configJson);
    final result = await executeResultWithRetry<GoogleDriveUploadResult>(
      isCancelled: isCancelled,
      operation: () async {
        if (isCancelled != null && isCancelled()) {
          return _cancelledFailure();
        }
        return _sendToGoogleDrive.call(
          sourceFilePath: sourceFilePath,
          config: config,
          customFileName: _buildCustomFileName(sourceFilePath, backupId),
          onProgress: onProgress,
          isCancelled: isCancelled,
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
    final breakerFailure = _circuitBreakerGuard(destination);
    if (breakerFailure != null) return breakerFailure;
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);

    final config = DropboxDestinationConfig.fromJson(configJson);
    final result = await executeResultWithRetry<DropboxUploadResult>(
      isCancelled: isCancelled,
      operation: () async {
        if (isCancelled != null && isCancelled()) {
          return _cancelledFailure();
        }
        return _sendToDropbox.call(
          sourceFilePath: sourceFilePath,
          config: config,
          customFileName: _buildCustomFileName(sourceFilePath, backupId),
          onProgress: onProgress,
          isCancelled: isCancelled,
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
    final breakerFailure = _circuitBreakerGuard(destination);
    if (breakerFailure != null) return breakerFailure;
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);

    final config = NextcloudDestinationConfig.fromJson(configJson);
    final result = await executeResultWithRetry<NextcloudUploadResult>(
      isCancelled: isCancelled,
      operation: () async {
        if (isCancelled != null && isCancelled()) {
          return _cancelledFailure();
        }
        return _sendToNextcloud.call(
          sourceFilePath: sourceFilePath,
          config: config,
          customFileName: _buildCustomFileName(sourceFilePath, backupId),
          onProgress: onProgress,
          isCancelled: isCancelled,
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

  /// Faz parse defensivo do JSON de configuração da destination. Antes
  /// um JSON inválido virava `BackupFailure` genérica vinda do
  /// `try/catch` externo, sem indicar a causa real para o usuário. Agora
  /// devolvemos uma `ValidationFailure` com mensagem clara.
  rd.Result<Map<String, dynamic>> _parseConfigJson(
    BackupDestination destination,
  ) {
    try {
      final decoded = jsonDecode(destination.config);
      if (decoded is! Map<String, dynamic>) {
        return rd.Failure(
          ValidationFailure(
            message:
                'Configuração da destination "${destination.name}" não é '
                'um objeto JSON válido.',
          ),
        );
      }
      return rd.Success(decoded);
    } on FormatException catch (e) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Configuração JSON da destination "${destination.name}" está '
              'malformada: ${e.message}',
          originalError: e,
        ),
      );
    } on Object catch (e) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Erro inesperado ao ler configuração de "${destination.name}": '
              '$e',
          originalError: e,
        ),
      );
    }
  }

  /// Verifica se o circuit breaker permite o request. Retorna `null` se
  /// permite, ou uma `Failure` pré-construída se está aberto. Centraliza
  /// o bloco de 12 linhas que era duplicado em FTP/Drive/Dropbox/Nextcloud.
  rd.Failure<void, Exception>? _circuitBreakerGuard(
    BackupDestination destination,
  ) {
    final breaker = _circuitBreakerRegistry.getBreaker(destination.id);
    // tryAcquire (em vez de allowsRequest) reserva o slot em half-open
    // para evitar saturar o destino com requests paralelas durante o
    // probe period. O slot é liberado em recordSuccess/recordFailure.
    if (breaker.tryAcquire()) return null;
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

  /// Constrói o nome customizado para a destination quando há `backupId`.
  /// Antes essa lógica estava duplicada em 5 pontos do orchestrator.
  String? _buildCustomFileName(String sourceFilePath, String? backupId) {
    if (backupId == null) return null;
    return SybaseBackupPathSuffix.buildDestinationName(
      p.basename(sourceFilePath),
      backupId,
    );
  }

  /// Falha pré-construída para upload cancelado pelo usuário. Delega
  /// para [UploadCancellation.cancelledResult] (helper compartilhado
  /// com os destination services). Mantemos esta camada fina aqui
  /// porque vários sites neste arquivo já chamam `_cancelledFailure()`
  /// — trocar todos pelo helper externo é puro renomear cosmético.
  rd.Result<T> _cancelledFailure<T extends Object>() =>
      UploadCancellation.cancelledResult<T>();
}

/// Resolve o paralelismo máximo de uploads simultâneos a partir da
/// variável `BACKUP_DATABASE_MAX_PARALLEL_UPLOADS`, com clamp em [1, 16].
/// Antes valores inválidos caíam silenciosamente no default — agora
/// emitimos warning para facilitar diagnóstico de typos.
int _resolveMaxParallelUploads() {
  const envKey = 'BACKUP_DATABASE_MAX_PARALLEL_UPLOADS';
  const hardCap = 16;

  final raw = Platform.environment[envKey]?.trim();
  if (raw == null || raw.isEmpty) {
    return UploadParallelismConstants.maxParallelUploads;
  }

  final parsed = int.tryParse(raw);
  if (parsed == null) {
    LoggerService.warning(
      '[destination_orchestrator] $envKey="$raw" não é um inteiro válido. '
      'Usando default ${UploadParallelismConstants.maxParallelUploads}.',
    );
    return UploadParallelismConstants.maxParallelUploads;
  }
  if (parsed < 1) {
    LoggerService.warning(
      '[destination_orchestrator] $envKey=$parsed inválido (precisa ser '
      '>= 1). Usando default ${UploadParallelismConstants.maxParallelUploads}.',
    );
    return UploadParallelismConstants.maxParallelUploads;
  }
  if (parsed > hardCap) {
    LoggerService.warning(
      '[destination_orchestrator] $envKey=$parsed excede o teto de '
      '$hardCap (proteção contra exaustão de conexões). Limitando.',
    );
    return hardCap;
  }
  return parsed;
}
