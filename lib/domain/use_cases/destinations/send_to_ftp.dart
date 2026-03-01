import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
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
    if (sourceFilePath.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Caminho do arquivo não pode ser vazio'),
      );
    }
    if (config.host.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Host FTP não pode ser vazio'),
      );
    }

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
