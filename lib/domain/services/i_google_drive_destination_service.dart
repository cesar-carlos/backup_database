import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:result_dart/result_dart.dart' as rd;

class GoogleDriveUploadResult {
  const GoogleDriveUploadResult({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.duration,
  });
  final String fileId;
  final String fileName;
  final int fileSize;
  final Duration duration;
}

abstract class IGoogleDriveDestinationService {
  Future<rd.Result<GoogleDriveUploadResult>> upload({
    required String sourceFilePath,
    required GoogleDriveDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
  });

  Future<rd.Result<bool>> testConnection(GoogleDriveDestinationConfig config);

  Future<rd.Result<int>> cleanOldBackups({
    required GoogleDriveDestinationConfig config,
  });
}
