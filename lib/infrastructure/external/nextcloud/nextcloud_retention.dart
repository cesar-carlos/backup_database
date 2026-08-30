import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/nextcloud_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/protected_backup_file.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_folder_ops.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_http_client.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_webdav_utils.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NextcloudRetention {
  NextcloudRetention(this._httpClient, this._folderOps);

  final NextcloudHttpClient _httpClient;
  final NextcloudFolderOps _folderOps;

  Future<rd.Result<int>> cleanOldBackups({
    required NextcloudDestinationConfig config,
  }) async {
    try {
      final password = EncryptionService.decrypt(config.appPassword);
      final dio = _httpClient.create(config: config, password: password);

      final baseFolderPath = NextcloudWebdavUtils.buildBaseFolderPath(
        remotePath: config.remotePath,
        folderName: config.folderName,
      );

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      final folders = await _withRetry<List<String>>(
        attempts: 3,
        delay: const Duration(seconds: 2),
        label: 'list_collections Nextcloud',
        operation: () => _folderOps.listCollections(
          dio: dio,
          config: config,
          path: baseFolderPath,
        ),
      );

      var deletedCount = 0;
      for (final folderName in folders) {
        try {
          final folderDate = DateFormat('yyyy-MM-dd').parse(folderName);
          if (folderDate.isBefore(cutoffDate)) {
            final folderPath = NextcloudWebdavUtils.joinRemote(
              baseFolderPath,
              folderName,
            );

            final hasProtectedFile = await _folderHasProtectedFile(
              dio: dio,
              config: config,
              folderPath: folderPath,
              protectedShortIds: config.protectedBackupIdShortPrefixes,
            );
            if (hasProtectedFile) {
              LoggerService.debug(
                'Pasta Nextcloud protegida (retenção Sybase): $folderName',
              );
              continue;
            }

            final deleteUrl = NextcloudWebdavUtils.buildDavUrl(
              serverUrl: config.serverUrl,
              username: config.username,
              path: folderPath,
            );

            await dio.deleteUri(deleteUrl);
            deletedCount++;
          }
        } on Object catch (e) {
          LoggerService.debug(
            'Nextcloud: nome de pasta não é data válida, ignorando: $folderName — $e',
          );
        }
      }

      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao limpar backups Nextcloud',
        e,
        stackTrace,
      );
      return rd.Failure(
        NextcloudFailure(
          message: 'Erro ao limpar backups Nextcloud: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<bool> _folderHasProtectedFile({
    required Dio dio,
    required NextcloudDestinationConfig config,
    required String folderPath,
    required Set<String> protectedShortIds,
  }) async {
    if (protectedShortIds.isEmpty) return false;

    try {
      final names = await _folderOps.listDirectChildNames(
        dio: dio,
        config: config,
        folderPath: folderPath,
      );
      return ProtectedBackupFile.anyMatches(names, protectedShortIds);
    } on Object catch (e) {
      LoggerService.debug(
        'Nextcloud: erro ao listar pasta $folderPath — $e',
      );
    }
    return false;
  }

  /// Retry com delay constante para operações pontuais (lista de pastas,
  /// HEAD de integridade). Não usado no upload propriamente dito, que já
  /// tem retry no loop principal.
  Future<T> _withRetry<T>({
    required int attempts,
    required Duration delay,
    required String label,
    required Future<T> Function() operation,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var i = 1; i <= attempts; i++) {
      try {
        return await operation();
      } on Object catch (e, s) {
        lastError = e;
        lastStack = s;
        LoggerService.warning(
          'Nextcloud: $label falhou na tentativa $i/$attempts: $e',
        );
        if (i < attempts) await Future.delayed(delay);
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('Nextcloud retry sem erro registrado'),
      lastStack ?? StackTrace.current,
    );
  }
}
