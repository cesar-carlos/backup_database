import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/use_cases/destinations/destination_use_case.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendToLocal extends DestinationUseCase<LocalDestinationConfig, LocalUploadResult> {
  SendToLocal(this._service);
  final ILocalDestinationService _service;

  @override
  Future<rd.Result<LocalUploadResult>> execute({
    required String sourceFilePath,
    required LocalDestinationConfig config,
    String? customFileName,
  }) async {
    // Validate parameters
    final validationResult = validateParams(sourceFilePath, config);
    if (validationResult.isError()) {
      return rd.Failure(validationResult.exceptionOrNull()!);
    }

    // Execute upload
    return _service.upload(
      sourceFilePath: sourceFilePath,
      config: config,
      customFileName: customFileName,
    );
  }

  @override
  rd.Result<void> validateConfig(LocalDestinationConfig config) {
    if (config.path.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Caminho de destino não pode ser vazio'),
      );
    }

    return const rd.Success(());
  }
}
