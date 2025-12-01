import '../entities/backup_log.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IBackupLogRepository {
  Future<rd.Result<List<BackupLog>>> getAll({int? limit, int? offset});
  Future<rd.Result<BackupLog>> create(BackupLog log);
  Future<rd.Result<List<BackupLog>>> getByBackupHistory(String backupHistoryId);
  Future<rd.Result<List<BackupLog>>> getByLevel(LogLevel level);
  Future<rd.Result<List<BackupLog>>> getByCategory(LogCategory category);
  Future<rd.Result<List<BackupLog>>> getByDateRange(
    DateTime start,
    DateTime end,
  );
  Future<rd.Result<List<BackupLog>>> search(String query);
  Future<rd.Result<int>> deleteOlderThan(DateTime date);
}
