import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToLocal {
  SendToLocal(this._service);
  final ILocalDestinationService _service;

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

    return _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
    );
  }
}
