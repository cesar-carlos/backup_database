import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:backup_database/domain/services/i_send_file_to_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendFileToDestinationService implements ISendFileToDestinationService {
  const SendFileToDestinationService({
    required IDestinationOrchestrator destinationOrchestrator,
  }) : _destinationOrchestrator = destinationOrchestrator;

  final IDestinationOrchestrator _destinationOrchestrator;

  @override
  Future<rd.Result<void>> sendFile({
    required String localFilePath,
    required BackupDestination destination,
    UploadProgressCallback? onProgress,
  }) async {
    LoggerService.info(
      'Enviando arquivo para destino: ${destination.name} '
      '(${destination.type.name})',
    );
    return _destinationOrchestrator.uploadToDestination(
      sourceFilePath: localFilePath,
      destination: destination,
      onProgress: onProgress,
    );
  }
}
