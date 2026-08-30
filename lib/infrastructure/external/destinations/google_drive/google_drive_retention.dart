import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_folder_ops.dart';
import 'package:backup_database/infrastructure/external/destinations/protected_backup_file.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import 'package:result_dart/result_dart.dart' as rd;

class GoogleDriveRetention {
  GoogleDriveRetention(this._authClient, this._folderOps);

  final GoogleDriveAuthClient _authClient;
  final GoogleDriveFolderOps _folderOps;

  Future<rd.Result<int>> cleanOldBackups({
    required GoogleDriveDestinationConfig config,
  }) async {
    try {
      LoggerService.info('Limpando backups antigos no Google Drive');

      final authResult = await _authClient.getAuthenticatedClient();
      if (authResult.isError()) {
        return rd.Failure(authResult.exceptionOrNull()!);
      }

      final mainFolderId = await _folderOps.getOrCreateFolder(
        config.folderName,
        config.folderId,
      );

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      final folders = await _authClient.executeWithTokenRefresh<drive.FileList>(
        () async {
          final clientResult = await _authClient.getAuthenticatedClient();
          if (clientResult.isError()) {
            throw clientResult.exceptionOrNull()!;
          }

          final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
          final query =
              "'$mainFolderId' in parents and "
              "mimeType = 'application/vnd.google-apps.folder' and trashed = false";

          return driveApi.files.list(
            q: query,
            spaces: 'drive',
            $fields: 'files(id, name, createdTime)',
          );
        },
      );

      var deletedCount = 0;
      for (final folder in folders.files ?? const <drive.File>[]) {
        try {
          final folderName = folder.name;
          if (folderName == null || folderName.isEmpty) continue;
          final folderDate = DateFormat('yyyy-MM-dd').parse(folderName);
          if (folderDate.isBefore(cutoffDate)) {
            final folderId = folder.id;
            if (folderId == null) continue;

            final hasProtectedFile = await _folderHasProtectedFile(
              folderId,
              config.protectedBackupIdShortPrefixes,
            );
            if (hasProtectedFile) {
              LoggerService.debug(
                'Pasta Google Drive protegida (retenção Sybase): $folderName',
              );
              continue;
            }

            await _authClient.executeWithTokenRefresh(() async {
              final clientResult = await _authClient.getAuthenticatedClient();
              if (clientResult.isError()) {
                throw clientResult.exceptionOrNull()!;
              }

              final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
              await driveApi.files.delete(folderId);
            });
            deletedCount++;
            LoggerService.debug('Pasta deletada: $folderName');
          }
        } on Object catch (e) {
          LoggerService.debug('Erro ao deletar pasta vazia: $e');
        }
      }

      LoggerService.info(
        '$deletedCount pastas antigas removidas do Google Drive',
      );
      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao limpar backups Google Drive',
        e,
        stackTrace,
      );
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao limpar backups Google Drive: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<bool> _folderHasProtectedFile(
    String folderId,
    Set<String> protectedShortIds,
  ) async {
    if (protectedShortIds.isEmpty) return false;

    final fileList = await _authClient.executeWithTokenRefresh<drive.FileList>(
      () async {
        final clientResult = await _authClient.getAuthenticatedClient();
        if (clientResult.isError()) {
          throw clientResult.exceptionOrNull()!;
        }

        final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
        final query = "'$folderId' in parents and trashed = false";

        return driveApi.files.list(
          q: query,
          spaces: 'drive',
          $fields: 'files(name)',
        );
      },
    );

    return ProtectedBackupFile.anyMatches(
      (fileList.files ?? const <drive.File>[]).map((file) => file.name),
      protectedShortIds,
    );
  }
}
