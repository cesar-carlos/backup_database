import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:result_dart/result_dart.dart';

abstract class ISendFileToDestinationService {
  Future<Result<void>> sendFile({
    required String localFilePath,
    required BackupDestination destination,
    UploadProgressCallback? onProgress,
  });
}
