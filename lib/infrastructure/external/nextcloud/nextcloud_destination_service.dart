import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/nextcloud_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_errors.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_folder_ops.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_http_client.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_integrity_verifier.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_retention.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_uploader.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_webdav_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NextcloudDestinationService implements INextcloudDestinationService {
  factory NextcloudDestinationService() {
    const httpClient = NextcloudHttpClient();
    const folderOps = NextcloudFolderOps();
    const integrity = NextcloudIntegrityVerifier();
    return NextcloudDestinationService._(
      httpClient,
      NextcloudUploader(httpClient, folderOps, integrity),
      NextcloudRetention(httpClient, folderOps),
    );
  }

  NextcloudDestinationService._(
    this._httpClient,
    this._uploader,
    this._retention,
  );

  final NextcloudHttpClient _httpClient;
  final NextcloudUploader _uploader;
  final NextcloudRetention _retention;

  @override
  Future<rd.Result<NextcloudUploadResult>> upload({
    required String sourceFilePath,
    required NextcloudDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) {
    return _uploader.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
      maxRetries: maxRetries,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  @visibleForTesting
  static String getNextcloudErrorMessage(Object? e) =>
      NextcloudErrors.describe(e);

  @override
  Future<rd.Result<bool>> testConnection(
    NextcloudDestinationConfig config,
  ) async {
    try {
      final password = EncryptionService.decrypt(config.appPassword);
      final dio = _httpClient.create(config: config, password: password);

      final testUrl = NextcloudWebdavUtils.buildDavUrl(
        serverUrl: config.serverUrl,
        username: config.username,
        path: '/',
      );

      final response = await dio.requestUri(
        testUrl,
        options: Options(method: 'PROPFIND', headers: {'Depth': '0'}),
      );

      final statusCode = response.statusCode;
      if (statusCode != null && (statusCode == 200 || statusCode == 207)) {
        return const rd.Success(true);
      }

      return const rd.Success(false);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao testar conexão Nextcloud',
        e,
        stackTrace,
      );
      return rd.Failure(
        NextcloudFailure(
          message:
              'Erro ao testar conexão Nextcloud: ${NextcloudErrors.describe(e)}',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<int>> cleanOldBackups({
    required NextcloudDestinationConfig config,
  }) {
    return _retention.cleanOldBackups(config: config);
  }
}
