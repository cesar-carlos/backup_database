import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../infrastructure/external/destinations/local_destination_service.dart';

class SendToLocal {
  final LocalDestinationService _service;

  SendToLocal(this._service);

  Future<rd.Result<LocalUploadResult>> call({
    required String sourceFilePath,
    required LocalDestinationConfig config,
    String? customFileName,
  }) async {
    if (sourceFilePath.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Caminho do arquivo não pode ser vazio'),
      );
    }
    if (config.path.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Caminho de destino não pode ser vazio'),
      );
    }

    return await _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
    );
  }
}

