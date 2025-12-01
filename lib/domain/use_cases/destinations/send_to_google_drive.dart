import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../infrastructure/external/destinations/google_drive_destination_service.dart';

class SendToGoogleDrive {
  final GoogleDriveDestinationService _service;

  SendToGoogleDrive(this._service);

  Future<rd.Result<GoogleDriveUploadResult>> call({
    required String sourceFilePath,
    required GoogleDriveDestinationConfig config,
    String? customFileName,
  }) async {
    if (sourceFilePath.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Caminho do arquivo não pode ser vazio'),
      );
    }
    if (config.folderId.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'ID da pasta do Google Drive não pode ser vazio',
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

