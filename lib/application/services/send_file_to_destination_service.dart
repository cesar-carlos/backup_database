import 'dart:convert';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/i_send_file_to_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_dropbox.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_ftp.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_nextcloud.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class SendFileToDestinationService implements ISendFileToDestinationService {
  SendFileToDestinationService({
    required ILocalDestinationService localDestinationService,
    required SendToFtp sendToFtp,
    required IGoogleDriveDestinationService googleDriveDestinationService,
    required SendToDropbox sendToDropbox,
    required SendToNextcloud sendToNextcloud,
    required ILicensePolicyService licensePolicyService,
  }) : _localDestinationService = localDestinationService,
       _sendToFtp = sendToFtp,
       _googleDriveDestinationService = googleDriveDestinationService,
       _sendToDropbox = sendToDropbox,
       _sendToNextcloud = sendToNextcloud,
       _licensePolicyService = licensePolicyService;

  final ILocalDestinationService _localDestinationService;
  final SendToFtp _sendToFtp;
  final IGoogleDriveDestinationService _googleDriveDestinationService;
  final SendToDropbox _sendToDropbox;
  final SendToNextcloud _sendToNextcloud;
  final ILicensePolicyService _licensePolicyService;

  @override
  Future<rd.Result<void>> sendFile({
    required String localFilePath,
    required BackupDestination destination,
    UploadProgressCallback? onProgress,
  }) async {
    try {
      final licenseCheck =
          await _licensePolicyService.validateDestinationCapabilities(destination);
      if (licenseCheck.isError()) {
        return rd.Failure(licenseCheck.exceptionOrNull()!);
      }

      final configJson = jsonDecode(destination.config) as Map<String, dynamic>;

      switch (destination.type) {
        case DestinationType.local:
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

          // Verificar se o arquivo já está no destino (evita cópia desnecessária)
          final sourceFile = p.normalize(p.absolute(localFilePath));

          // Construir o caminho completo onde o arquivo seria salvo
          var destinationDir = config.path;
          if (config.createSubfoldersByDate) {
            final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
            destinationDir = p.join(config.path, dateFolder);
          }
          final finalDestinationPath = p.normalize(
            p.absolute(p.join(destinationDir, p.basename(localFilePath))),
          );

          // Verifica se o arquivo JÁ ESTÁ no caminho final de destino (case-insensitive no Windows)
          final fileAlreadyInDestination =
              sourceFile.toLowerCase() == finalDestinationPath.toLowerCase();

          if (fileAlreadyInDestination) {
            LoggerService.info(
              'Arquivo já está no destino local ${destination.name} '
              '($finalDestinationPath), pulando cópia',
            );
            // Arquivo já está no destino, não precisa copiar
            return const rd.Success(rd.unit);
          }

          LoggerService.info(
            'Copiando backup para destino local: ${destination.name} '
            '(${config.path})',
          );

          final uploadResult = await _localDestinationService.upload(
            sourceFilePath: localFilePath,
            config: config,
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

        case DestinationType.ftp:
          final config = FtpDestinationConfig.fromJson(configJson);

          LoggerService.info(
            'Enviando backup para FTP: ${destination.name} (${config.host})',
          );

          final uploadResult = await _sendToFtp.call(
            sourceFilePath: localFilePath,
            config: config,
            onProgress: onProgress,
            runId: LogContext.runId,
            destinationId: destination.id,
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

        case DestinationType.googleDrive:
          final config = GoogleDriveDestinationConfig(
            folderId: configJson['folderId'] as String,
            folderName: configJson['folderName'] as String? ?? 'Backups',
            accessToken: configJson['accessToken'] as String? ?? '',
            refreshToken: configJson['refreshToken'] as String? ?? '',
          );
          final result = await _googleDriveDestinationService.upload(
            sourceFilePath: localFilePath,
            config: config,
            onProgress: onProgress,
          );
          return result.fold(
            (_) => const rd.Success(()),
            rd.Failure.new,
          );

        case DestinationType.dropbox:
          final config = DropboxDestinationConfig(
            folderPath: configJson['folderPath'] as String? ?? '',
            folderName: configJson['folderName'] as String? ?? 'Backups',
          );
          final result = await _sendToDropbox.call(
            sourceFilePath: localFilePath,
            config: config,
            onProgress: onProgress,
          );
          return result.fold(
            (_) => const rd.Success(()),
            rd.Failure.new,
          );

        case DestinationType.nextcloud:
          final config = NextcloudDestinationConfig.fromJson(configJson);
          final result = await _sendToNextcloud.call(
            sourceFilePath: localFilePath,
            config: config,
            onProgress: onProgress,
          );
          return result.fold(
            (_) => const rd.Success(()),
            rd.Failure.new,
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
