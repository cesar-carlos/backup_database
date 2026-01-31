import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FtpUploadResult {
  const FtpUploadResult({
    required this.remotePath,
    required this.fileSize,
    required this.duration,
  });
  final String remotePath;
  final int fileSize;
  final Duration duration;
}

abstract class IFtpService {
  Future<rd.Result<FtpUploadResult>> upload({
    required String sourceFilePath,
    required FtpDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
  });

  Future<rd.Result<bool>> testConnection(FtpDestinationConfig config);

  Future<rd.Result<int>> cleanOldBackups({
    required FtpDestinationConfig config,
  });
}
