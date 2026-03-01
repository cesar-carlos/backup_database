import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FtpUploadResult {
  const FtpUploadResult({
    required this.remotePath,
    required this.fileSize,
    required this.duration,
    this.sha256,
    this.hashDurationMs,
  });
  final String remotePath;
  final int fileSize;
  final Duration duration;
  final String? sha256;
  final int? hashDurationMs;
}

class FtpConnectionTestResult {
  const FtpConnectionTestResult({
    required this.connected,
    this.supportsRestStream,
    this.canWrite,
    this.canRename,
  });
  final bool connected;
  final bool? supportsRestStream;
  final bool? canWrite;
  final bool? canRename;

  bool get ok => connected;

  bool get hasCompatibilityWarnings =>
      connected &&
      (canWrite == false || canRename == false);
}

abstract class IFtpService {
  Future<rd.Result<FtpUploadResult>> upload({
    required String sourceFilePath,
    required FtpDestinationConfig config,
    String? customFileName,
    int maxRetries = 1,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
    String? runId,
    String? destinationId,
  });

  Future<rd.Result<FtpConnectionTestResult>> testConnection(
    FtpDestinationConfig config,
  );

  Future<rd.Result<int>> cleanOldBackups({
    required FtpDestinationConfig config,
  });
}
