import 'dart:convert';

import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_dropbox.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_ftp.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_nextcloud.dart';
import 'package:result_dart/result_dart.dart' as rd;

class DestinationOrchestratorImpl implements IDestinationOrchestrator {
  const DestinationOrchestratorImpl({
    required ILocalDestinationService localDestinationService,
    required SendToFtp sendToFtp,
    required IGoogleDriveDestinationService googleDriveDestinationService,
    required SendToDropbox sendToDropbox,
    required SendToNextcloud sendToNextcloud,
    required ILicenseValidationService licenseValidationService,
  }) : _localDestinationService = localDestinationService,
       _sendToFtp = sendToFtp,
       _googleDriveDestinationService = googleDriveDestinationService,
       _sendToDropbox = sendToDropbox,
       _sendToNextcloud = sendToNextcloud,
       _licenseValidationService = licenseValidationService;

  final ILocalDestinationService _localDestinationService;
  final SendToFtp _sendToFtp;
  final IGoogleDriveDestinationService _googleDriveDestinationService;
  final SendToDropbox _sendToDropbox;
  final SendToNextcloud _sendToNextcloud;
  final ILicenseValidationService _licenseValidationService;

  @override
  Future<rd.Result<void>> uploadToDestination({
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
          return await _uploadToLocal(
            sourceFilePath,
            destination,
            configJson,
          );

        case DestinationType.ftp:
          return await _uploadToFtp(
            sourceFilePath,
            destination,
            configJson,
          );

        case DestinationType.googleDrive:
          return await _uploadToGoogleDrive(
            sourceFilePath,
            destination,
            configJson,
          );

        case DestinationType.dropbox:
          return await _uploadToDropbox(
            sourceFilePath,
            destination,
            configJson,
          );

        case DestinationType.nextcloud:
          return await _uploadToNextcloud(
            sourceFilePath,
            destination,
            configJson,
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
  }) async {
    final results = <rd.Result<void>>[];

    for (final destination in destinations) {
      final result = await uploadToDestination(
        sourceFilePath: sourceFilePath,
        destination: destination,
      );
      results.add(result);
    }

    return results;
  }

  Future<rd.Result<void>> _ensureDestinationFeatureAllowed(
    BackupDestination destination,
  ) async {
    String? requiredFeature;
    switch (destination.type) {
      case DestinationType.googleDrive:
        requiredFeature = LicenseFeatures.googleDrive;
      case DestinationType.dropbox:
        requiredFeature = LicenseFeatures.dropbox;
      case DestinationType.nextcloud:
        requiredFeature = LicenseFeatures.nextcloud;
      case DestinationType.local:
      case DestinationType.ftp:
        requiredFeature = null;
    }

    if (requiredFeature == null) {
      return const rd.Success(());
    }

    final allowedResult = await _licenseValidationService.isFeatureAllowed(
      requiredFeature,
    );
    final allowed = allowedResult.getOrElse((_) => false);
    if (!allowed) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Destino ${destination.name} requer licença '
              '(${destination.type.name}).',
        ),
      );
    }

    return const rd.Success(());
  }

  Future<rd.Result<void>> _uploadToLocal(
    String sourceFilePath,
    BackupDestination destination,
    Map<String, dynamic> configJson,
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

    final uploadResult = await _localDestinationService.upload(
      sourceFilePath: sourceFilePath,
      config: config,
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
  ) async {
    final config = FtpDestinationConfig(
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
          '(${_formatBytes(result.fileSize)} em '
          '${result.duration.inSeconds}s)',
        );
        return const rd.Success(());
      },
      (failure) {
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
  ) async {
    final config = GoogleDriveDestinationConfig(
      folderId: configJson['folderId'] as String,
      folderName: configJson['folderName'] as String? ?? 'Backups',
      accessToken: configJson['accessToken'] as String? ?? '',
      refreshToken: configJson['refreshToken'] as String? ?? '',
    );
    final result = await _googleDriveDestinationService.upload(
      sourceFilePath: sourceFilePath,
      config: config,
    );
    return result.fold(
      (_) => const rd.Success(()),
      rd.Failure.new,
    );
  }

  Future<rd.Result<void>> _uploadToDropbox(
    String sourceFilePath,
    BackupDestination destination,
    Map<String, dynamic> configJson,
  ) async {
    final config = DropboxDestinationConfig(
      folderPath: configJson['folderPath'] as String? ?? '',
      folderName: configJson['folderName'] as String? ?? 'Backups',
    );
    final result = await _sendToDropbox.call(
      sourceFilePath: sourceFilePath,
      config: config,
    );
    return result.fold(
      (_) => const rd.Success(()),
      rd.Failure.new,
    );
  }

  Future<rd.Result<void>> _uploadToNextcloud(
    String sourceFilePath,
    BackupDestination destination,
    Map<String, dynamic> configJson,
  ) async {
    final config = NextcloudDestinationConfig.fromJson(configJson);
    final result = await _sendToNextcloud.call(
      sourceFilePath: sourceFilePath,
      config: config,
    );
    return result.fold(
      (_) => const rd.Success(()),
      rd.Failure.new,
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
