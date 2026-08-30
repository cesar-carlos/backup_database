import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/protected_backup_file.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_client.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:result_dart/result_dart.dart' as rd;

class DropboxRetention {
  DropboxRetention(this._authClient);
  final DropboxAuthClient _authClient;

  Future<rd.Result<int>> cleanOldBackups({
    required DropboxDestinationConfig config,
  }) async {
    try {
      final dioResult = await _authClient.getAuthenticatedDio();
      if (dioResult.isError()) {
        return rd.Failure(dioResult.exceptionOrNull()!);
      }

      final mainFolderPath = config.folderPath.isEmpty
          ? '/${config.folderName}'
          : '${config.folderPath}/${config.folderName}';

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      final dio = dioResult.getOrNull()!;

      final folders = await _authClient.executeWithTokenRefresh(() async {
        final response = await dio.post(
          '/2/files/list_folder',
          data: {'path': mainFolderPath},
        );

        final data = response.data as Map<String, dynamic>;
        return data['entries'] as List<dynamic>? ?? [];
      });

      var deletedCount = 0;
      for (final folder in folders) {
        final folderData = folder as Map<String, dynamic>;
        final folderName = folderData['name'] as String?;
        final folderPath =
            folderData['path_display'] as String? ??
            folderData['path_lower'] as String?;

        if (folderName == null || folderPath == null) continue;

        try {
          final folderDate = DateFormat('yyyy-MM-dd').parse(folderName);
          if (folderDate.isBefore(cutoffDate)) {
            final hasProtectedFile = await _folderHasProtectedFile(
              dio,
              folderPath,
              config.protectedBackupIdShortPrefixes,
            );
            if (hasProtectedFile) {
              LoggerService.debug(
                'Pasta Dropbox protegida (retenção Sybase): $folderName',
              );
              continue;
            }

            await _authClient.executeWithTokenRefresh(() async {
              await dio.post('/2/files/delete_v2', data: {'path': folderPath});
            });
            deletedCount++;
          }
        } on Object catch (e, s) {
          LoggerService.error(
            'Falha ao remover pasta antiga do Dropbox: $folderPath',
            e,
            s,
          );
        }
      }

      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao limpar backups Dropbox', e, stackTrace);
      return rd.Failure(
        DropboxFailure(
          message: 'Erro ao limpar backups Dropbox: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<bool> _folderHasProtectedFile(
    Dio dio,
    String folderPath,
    Set<String> protectedShortIds,
  ) async {
    if (protectedShortIds.isEmpty) return false;

    try {
      final entries = await _authClient.executeWithTokenRefresh(() async {
        final response = await dio.post(
          '/2/files/list_folder',
          data: {'path': folderPath},
        );
        final data = response.data as Map<String, dynamic>?;
        return data?['entries'] as List<dynamic>? ?? [];
      });

      for (final entry in entries) {
        final entryData = entry as Map<String, dynamic>;
        final tag = entryData['.tag'] as String?;
        if (tag != 'file') continue;

        if (ProtectedBackupFile.matchesName(
          entryData['name'] as String?,
          protectedShortIds,
        )) {
          return true;
        }
      }
    } on Object catch (e, s) {
      LoggerService.debug(
        'Erro ao listar pasta Dropbox: $folderPath — $e',
        s,
      );
    }
    return false;
  }
}
