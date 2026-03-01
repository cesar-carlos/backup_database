import 'dart:convert';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_dropbox_destination_service.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class CleanOldBackupsResult {
  const CleanOldBackupsResult({
    this.localDeleted = 0,
    this.ftpDeleted = 0,
    this.googleDriveDeleted = 0,
    this.dropboxDeleted = 0,
    this.nextcloudDeleted = 0,
  });
  final int localDeleted;
  final int ftpDeleted;
  final int googleDriveDeleted;
  final int dropboxDeleted;
  final int nextcloudDeleted;

  int get total =>
      localDeleted +
      ftpDeleted +
      googleDriveDeleted +
      dropboxDeleted +
      nextcloudDeleted;
}

class CleanOldBackups {
  CleanOldBackups({
    required ILocalDestinationService localService,
    required IFtpService ftpService,
    required IGoogleDriveDestinationService googleDriveService,
    required IDropboxDestinationService dropboxService,
    required INextcloudDestinationService nextcloudService,
  }) : _localService = localService,
       _ftpService = ftpService,
       _googleDriveService = googleDriveService,
       _dropboxService = dropboxService,
       _nextcloudService = nextcloudService;
  final ILocalDestinationService _localService;
  final IFtpService _ftpService;
  final IGoogleDriveDestinationService _googleDriveService;
  final IDropboxDestinationService _dropboxService;
  final INextcloudDestinationService _nextcloudService;

  Future<rd.Result<CleanOldBackupsResult>> call(
    List<BackupDestination> destinations,
  ) async {
    LoggerService.info('Iniciando limpeza de backups antigos');

    var localDeleted = 0;
    var ftpDeleted = 0;
    var googleDriveDeleted = 0;
    var dropboxDeleted = 0;
    var nextcloudDeleted = 0;

    for (final destination in destinations) {
      if (!destination.enabled) continue;

      try {
        final configJson =
            jsonDecode(destination.config) as Map<String, dynamic>;

        switch (destination.type) {
          case DestinationType.local:
            final config = LocalDestinationConfig(
              path: configJson['path'] as String,
              createSubfoldersByDate:
                  configJson['createSubfoldersByDate'] as bool? ?? true,
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final result = await _localService.cleanOldBackups(config: config);
            result.fold((count) => localDeleted += count, (exception) {
              final failure = exception as Failure;
              LoggerService.warning('Erro ao limpar local: ${failure.message}');
            });

          case DestinationType.ftp:
            final config = FtpDestinationConfig.fromJson(configJson);
            final result = await _ftpService.cleanOldBackups(config: config);
            result.fold((count) => ftpDeleted += count, (exception) {
              final failure = exception as Failure;
              LoggerService.warning('Erro ao limpar FTP: ${failure.message}');
            });

          case DestinationType.googleDrive:
            final config = GoogleDriveDestinationConfig(
              folderId: configJson['folderId'] as String,
              folderName: configJson['folderName'] as String? ?? 'Backups',
              accessToken: configJson['accessToken'] as String? ?? '',
              refreshToken: configJson['refreshToken'] as String? ?? '',
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final result = await _googleDriveService.cleanOldBackups(
              config: config,
            );
            result.fold((count) => googleDriveDeleted += count, (exception) {
              final failure = exception as Failure;
              LoggerService.warning(
                'Erro ao limpar Google Drive: ${failure.message}',
              );
            });

          case DestinationType.dropbox:
            final config = DropboxDestinationConfig(
              folderPath: configJson['folderPath'] as String? ?? '',
              folderName: configJson['folderName'] as String? ?? 'Backups',
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final result = await _dropboxService.cleanOldBackups(
              config: config,
            );
            result.fold((count) => dropboxDeleted += count, (exception) {
              final failure = exception as Failure;
              LoggerService.warning(
                'Erro ao limpar Dropbox: ${failure.message}',
              );
            });

          case DestinationType.nextcloud:
            final config = NextcloudDestinationConfig.fromJson(configJson);
            final result = await _nextcloudService.cleanOldBackups(
              config: config,
            );
            result.fold((count) => nextcloudDeleted += count, (exception) {
              final failure = exception as Failure;
              LoggerService.warning(
                'Erro ao limpar Nextcloud: ${failure.message}',
              );
            });
        }
      } on Object catch (e) {
        LoggerService.warning(
          'Erro ao processar destino ${destination.name}: $e',
        );
      }
    }

    final result = CleanOldBackupsResult(
      localDeleted: localDeleted,
      ftpDeleted: ftpDeleted,
      googleDriveDeleted: googleDriveDeleted,
      dropboxDeleted: dropboxDeleted,
      nextcloudDeleted: nextcloudDeleted,
    );

    LoggerService.info('Limpeza concluída: ${result.total} arquivos removidos');
    return rd.Success(result);
  }
}
