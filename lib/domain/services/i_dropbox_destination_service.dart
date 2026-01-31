import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:result_dart/result_dart.dart' as rd;

class DropboxUploadResult {
  const DropboxUploadResult({
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

abstract class IDropboxDestinationService {
  Future<rd.Result<DropboxUploadResult>> upload({
    required String sourceFilePath,
    required DropboxDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
  });

  Future<rd.Result<bool>> testConnection(DropboxDestinationConfig config);

  Future<rd.Result<int>> cleanOldBackups({
    required DropboxDestinationConfig config,
  });
}
