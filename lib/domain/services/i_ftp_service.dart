import 'package:result_dart/result_dart.dart' as rd;

import '../entities/backup_destination.dart';

class FtpUploadResult {
  final String remotePath;
  final int fileSize;
  final Duration duration;

  const FtpUploadResult({
    required this.remotePath,
    required this.fileSize,
    required this.duration,
  });
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
