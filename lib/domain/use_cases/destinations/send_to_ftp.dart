import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../entities/backup_destination.dart';
import '../../services/i_ftp_service.dart';

class SendToFtp {
  final IFtpService _service;

  SendToFtp(this._service);

  Future<rd.Result<FtpUploadResult>> call({
    required String sourceFilePath,
    required FtpDestinationConfig config,
    String? customFileName,
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

    return await _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
    );
  }
}
