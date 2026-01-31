import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LocalUploadResult {
  const LocalUploadResult({
    required this.destinationPath,
    required this.fileSize,
    required this.duration,
  });
  final String destinationPath;
  final int fileSize;
  final Duration duration;
}

abstract class ILocalDestinationService {
  Future<rd.Result<LocalUploadResult>> upload({
    required String sourceFilePath,
    required LocalDestinationConfig config,
    String? customFileName,
  });

  Future<rd.Result<bool>> testConnection(LocalDestinationConfig config);

  Future<rd.Result<int>> cleanOldBackups({
    required LocalDestinationConfig config,
  });
}
