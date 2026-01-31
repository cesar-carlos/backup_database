import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToGoogleDrive {
  SendToGoogleDrive(this._service);
  final IGoogleDriveDestinationService _service;

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

    return _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
    );
  }
}
