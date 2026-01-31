import 'dart:convert';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive_destination_service.dart'
    as gd;
import 'package:backup_database/infrastructure/external/destinations/local_destination_service.dart'
    as local;
import 'package:backup_database/infrastructure/external/dropbox/dropbox_destination_service.dart'
    as dropbox;
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_destination_service.dart'
    as nextcloud;
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
    required local.LocalDestinationService localService,
    required IFtpService ftpService,
    required gd.GoogleDriveDestinationService googleDriveService,
    required dropbox.DropboxDestinationService dropboxService,
    required nextcloud.NextcloudDestinationService nextcloudService,
  }) : _localService = localService,
       _ftpService = ftpService,
       _googleDriveService = googleDriveService,
       _dropboxService = dropboxService,
       _nextcloudService = nextcloudService;
  final local.LocalDestinationService _localService;
  final IFtpService _ftpService;
  final gd.GoogleDriveDestinationService _googleDriveService;
  final dropbox.DropboxDestinationService _dropboxService;
  final nextcloud.NextcloudDestinationService _nextcloudService;

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
            final config = local.LocalDestinationConfig(
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
            final config = FtpDestinationConfig(
              host: configJson['host'] as String,
              port: configJson['port'] as int? ?? 21,
              username: configJson['username'] as String,
              password: configJson['password'] as String,
              remotePath: configJson['remotePath'] as String? ?? '/',
              useFtps: configJson['useFtps'] as bool? ?? false,
              retentionDays: configJson['retentionDays'] as int? ?? 30,
            );
            final result = await _ftpService.cleanOldBackups(config: config);
            result.fold((count) => ftpDeleted += count, (exception) {
              final failure = exception as Failure;
              LoggerService.warning('Erro ao limpar FTP: ${failure.message}');
            });

          case DestinationType.googleDrive:
            final config = gd.GoogleDriveDestinationConfig(
              folderId: configJson['folderId'] as String,
              folderName: configJson['folderName'] as String? ?? 'Backups',
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
            final config = dropbox.DropboxDestinationConfig(
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
