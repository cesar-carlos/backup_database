import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/domain/use_cases/destinations/destination_use_case.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToFtp {
  SendToFtp(this._service);
  final IFtpService _service;

  Future<rd.Result<FtpUploadResult>> call({
    required String sourceFilePath,
    required FtpDestinationConfig config,
    String? customFileName,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
    String? runId,
    String? destinationId,
  }) async {
    final pathCheck = DestinationUseCase.notEmptyOrFailure(
      sourceFilePath,
      'Caminho do arquivo',
    );
    if (pathCheck.isError()) return rd.Failure(pathCheck.exceptionOrNull()!);

    final hostCheck = DestinationUseCase.notEmptyOrFailure(
      config.host,
      'Host FTP',
    );
    if (hostCheck.isError()) return rd.Failure(hostCheck.exceptionOrNull()!);

    return _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
      onProgress: onProgress,
      isCancelled: isCancelled,
      runId: runId,
      destinationId: destinationId,
    );
  }
}
