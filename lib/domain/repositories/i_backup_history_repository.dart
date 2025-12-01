import '../entities/backup_history.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IBackupHistoryRepository {
  Future<rd.Result<List<BackupHistory>>> getAll({int? limit, int? offset});
  Future<rd.Result<BackupHistory>> getById(String id);
  Future<rd.Result<BackupHistory>> create(BackupHistory history);
  Future<rd.Result<BackupHistory>> update(BackupHistory history);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<BackupHistory>>> getBySchedule(String scheduleId);
  Future<rd.Result<List<BackupHistory>>> getByStatus(BackupStatus status);
  Future<rd.Result<List<BackupHistory>>> getByDateRange(
    DateTime start,
    DateTime end,
  );
  Future<rd.Result<BackupHistory>> getLastBySchedule(String scheduleId);
  Future<rd.Result<int>> deleteOlderThan(DateTime date);
}
