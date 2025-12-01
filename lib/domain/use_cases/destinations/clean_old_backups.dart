import 'dart:convert';

import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/utils/logger_service.dart';
import '../../../core/errors/failure.dart';
import '../../entities/backup_destination.dart';
import '../../../infrastructure/external/destinations/local_destination_service.dart'
    as local;
import '../../../infrastructure/external/destinations/ftp_destination_service.dart'
    as ftp;
import '../../../infrastructure/external/destinations/google_drive_destination_service.dart'
    as gd;

class CleanOldBackupsResult {
  final int localDeleted;
  final int ftpDeleted;
  final int googleDriveDeleted;

  const CleanOldBackupsResult({
    this.localDeleted = 0,
    this.ftpDeleted = 0,
    this.googleDriveDeleted = 0,
  });

  int get total => localDeleted + ftpDeleted + googleDriveDeleted;
}

class CleanOldBackups {
  final local.LocalDestinationService _localService;
  final ftp.FtpDestinationService _ftpService;
  final gd.GoogleDriveDestinationService _googleDriveService;

  CleanOldBackups({
    required local.LocalDestinationService localService,
    required ftp.FtpDestinationService ftpService,
    required gd.GoogleDriveDestinationService googleDriveService,
  })  : _localService = localService,
        _ftpService = ftpService,
        _googleDriveService = googleDriveService;

  Future<rd.Result<CleanOldBackupsResult>> call(
    List<BackupDestination> destinations,
  ) async {
    LoggerService.info('Iniciando limpeza de backups antigos');

    int localDeleted = 0;
    int ftpDeleted = 0;
    int googleDriveDeleted = 0;

    for (final destination in destinations) {
      if (!destination.enabled) continue;

      try {
        final configJson = jsonDecode(destination.config) as Map<String, dynamic>;

        switch (destination.type) {
          case DestinationType.local:
            final config = local.LocalDestinationConfig(
              path: configJson['path'] as String,
              createSubfoldersByDate:
                  configJson['createSubfoldersByDate'] as bool? ?? true,
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final result = await _localService.cleanOldBackups(config: config);
            result.fold(
              (count) => localDeleted += count,
              (exception) {
                final failure = exception as Failure;
                LoggerService.warning(
                  'Erro ao limpar local: ${failure.message}',
                );
              },
            );
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
            final result = await _ftpService.cleanOldBackups(config: config);
            result.fold(
              (count) => ftpDeleted += count,
              (exception) {
                final failure = exception as Failure;
                LoggerService.warning(
                  'Erro ao limpar FTP: ${failure.message}',
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
            final result = await _googleDriveService.cleanOldBackups(
              config: config,
            );
            result.fold(
              (count) => googleDriveDeleted += count,
              (exception) {
                final failure = exception as Failure;
                LoggerService.warning(
                  'Erro ao limpar Google Drive: ${failure.message}',
                );
              },
            );
            break;
        }
      } catch (e) {
        LoggerService.warning(
          'Erro ao processar destino ${destination.name}: $e',
        );
      }
    }

    final result = CleanOldBackupsResult(
      localDeleted: localDeleted,
      ftpDeleted: ftpDeleted,
      googleDriveDeleted: googleDriveDeleted,
    );

    LoggerService.info('Limpeza concluída: ${result.total} arquivos removidos');
    return rd.Success(result);
  }
}

