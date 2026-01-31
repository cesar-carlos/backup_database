import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_destination_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToDropbox {
  SendToDropbox(this._service);
  final DropboxDestinationService _service;

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

    return _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
    );
  }
}
