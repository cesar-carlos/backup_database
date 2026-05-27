import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/domain/use_cases/destinations/destination_use_case.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToGoogleDrive {
  SendToGoogleDrive(this._service);
  final IGoogleDriveDestinationService _service;

  Future<rd.Result<GoogleDriveUploadResult>> call({
    required String sourceFilePath,
    required GoogleDriveDestinationConfig config,
    String? customFileName,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final pathCheck = DestinationUseCase.notEmptyOrFailure(
      sourceFilePath,
      'Caminho do arquivo',
    );
    if (pathCheck.isError()) return rd.Failure(pathCheck.exceptionOrNull()!);

    final folderCheck = DestinationUseCase.notEmptyOrFailure(
      config.folderId,
      'ID da pasta do Google Drive',
    );
    if (folderCheck.isError()) {
      return rd.Failure(folderCheck.exceptionOrNull()!);
    }

    return _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}
