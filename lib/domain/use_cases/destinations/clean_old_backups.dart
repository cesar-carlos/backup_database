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
        final deleted = await _cleanForDestination(destination, configJson);

        switch (destination.type) {
          case DestinationType.local:
            localDeleted += deleted;
          case DestinationType.ftp:
            ftpDeleted += deleted;
          case DestinationType.googleDrive:
            googleDriveDeleted += deleted;
          case DestinationType.dropbox:
            dropboxDeleted += deleted;
          case DestinationType.nextcloud:
            nextcloudDeleted += deleted;
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

  /// Despacha a limpeza para o serviço apropriado e retorna o número de
  /// arquivos removidos. Centraliza o pattern de fold/log/cast inseguro
  /// que antes era replicado por destino (5 cópias quase idênticas).
  Future<int> _cleanForDestination(
    BackupDestination destination,
    Map<String, dynamic> configJson,
  ) async {
    final result = await _runCleanupByType(destination.type, configJson);
    return result.fold(
      (count) => count,
      (failure) {
        LoggerService.warning(
          'Erro ao limpar ${destination.type.name}: ${_failureMessage(failure)}',
        );
        return 0;
      },
    );
  }

  Future<rd.Result<int>> _runCleanupByType(
    DestinationType type,
    Map<String, dynamic> configJson,
  ) {
    switch (type) {
      case DestinationType.local:
        return _localService.cleanOldBackups(
          config: LocalDestinationConfig(
            path: configJson['path'] as String,
            createSubfoldersByDate:
                configJson['createSubfoldersByDate'] as bool? ?? true,
            retentionDays: configJson['retentionDays'] as int? ?? 30,
          ),
        );
      case DestinationType.ftp:
        return _ftpService.cleanOldBackups(
          config: FtpDestinationConfig.fromJson(configJson),
        );
      case DestinationType.googleDrive:
        return _googleDriveService.cleanOldBackups(
          config: GoogleDriveDestinationConfig(
            folderId: configJson['folderId'] as String,
            folderName: configJson['folderName'] as String? ?? 'Backups',
            accessToken: configJson['accessToken'] as String? ?? '',
            refreshToken: configJson['refreshToken'] as String? ?? '',
            retentionDays: configJson['retentionDays'] as int? ?? 30,
          ),
        );
      case DestinationType.dropbox:
        return _dropboxService.cleanOldBackups(
          config: DropboxDestinationConfig(
            folderPath: configJson['folderPath'] as String? ?? '',
            folderName: configJson['folderName'] as String? ?? 'Backups',
            retentionDays: configJson['retentionDays'] as int? ?? 30,
          ),
        );
      case DestinationType.nextcloud:
        return _nextcloudService.cleanOldBackups(
          config: NextcloudDestinationConfig.fromJson(configJson),
        );
    }
  }

  /// Helper para extrair mensagem amigável de qualquer Failure/Exception.
  /// Antes era reimplementado inline com `failure as Failure` (cast direto,
  /// crashava com tipos inesperados).
  String _failureMessage(Object failure) =>
      failure is Failure ? failure.message : failure.toString();
}
