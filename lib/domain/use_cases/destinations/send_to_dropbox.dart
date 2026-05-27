import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_dropbox_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/domain/use_cases/destinations/destination_use_case.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToDropbox {
  SendToDropbox(this._service);
  final IDropboxDestinationService _service;

  Future<rd.Result<DropboxUploadResult>> call({
    required String sourceFilePath,
    required DropboxDestinationConfig config,
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
      config.folderName,
      'Nome da pasta do Dropbox',
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
