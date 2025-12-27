import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../domain/entities/backup_destination.dart';
import '../../../infrastructure/external/nextcloud/nextcloud_destination_service.dart';

class SendToNextcloud {
  final NextcloudDestinationService _service;

  SendToNextcloud(this._service);

  Future<rd.Result<NextcloudUploadResult>> call({
    required String sourceFilePath,
    required NextcloudDestinationConfig config,
    String? customFileName,
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
        ValidationFailure(message: 'App Password do Nextcloud não pode ser vazio'),
      );
    }
    if (config.folderName.trim().isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Nome da pasta do Nextcloud não pode ser vazio'),
      );
    }

    return await _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
    );
  }
}


