import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NextcloudUploadResult {
  const NextcloudUploadResult({
    required this.remotePath,
    required this.fileSize,
    required this.duration,
  });
  final String remotePath;
  final int fileSize;
  final Duration duration;
}

abstract class INextcloudDestinationService {
  Future<rd.Result<NextcloudUploadResult>> upload({
    required String sourceFilePath,
    required NextcloudDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
    UploadProgressCallback? onProgress,
  });

  Future<rd.Result<bool>> testConnection(NextcloudDestinationConfig config);

  Future<rd.Result<int>> cleanOldBackups({
    required NextcloudDestinationConfig config,
  });
}
