import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToNextcloud {
  SendToNextcloud(this._service);
  final INextcloudDestinationService _service;

  Future<rd.Result<NextcloudUploadResult>> call({
    required String sourceFilePath,
    required NextcloudDestinationConfig config,
    String? customFileName,
    UploadProgressCallback? onProgress,
  }) async {
    if (sourceFilePath.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Caminho do arquivo não pode ser vazio'),
      );
    }
    if (config.serverUrl.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'URL do Nextcloud não pode ser vazia'),
      );
    }
    if (config.username.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Usuário do Nextcloud não pode ser vazio'),
      );
    }
    if (config.appPassword.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'App Password do Nextcloud não pode ser vazio',
        ),
      );
    }
    if (config.folderName.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Nome da pasta do Nextcloud não pode ser vazio',
        ),
      );
    }

    return _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
      onProgress: onProgress,
    );
  }
}
