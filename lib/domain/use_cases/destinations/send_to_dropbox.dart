import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../infrastructure/external/dropbox/dropbox_destination_service.dart';

class SendToDropbox {
  final DropboxDestinationService _service;

  SendToDropbox(this._service);

  Future<rd.Result<DropboxUploadResult>> call({
    required String sourceFilePath,
    required DropboxDestinationConfig config,
    String? customFileName,
  }) async {
    if (sourceFilePath.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Caminho do arquivo não pode ser vazio'),
      );
    }
    if (config.folderName.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Nome da pasta do Dropbox não pode ser vazio',
        ),
      );
    }

    return await _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
    );
  }
}
