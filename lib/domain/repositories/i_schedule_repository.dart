import '../entities/schedule.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IScheduleRepository {
  Future<rd.Result<List<Schedule>>> getAll();
  Future<rd.Result<Schedule>> getById(String id);
  Future<rd.Result<Schedule>> create(Schedule schedule);
  Future<rd.Result<Schedule>> update(Schedule schedule);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<Schedule>>> getEnabled();
  Future<rd.Result<List<Schedule>>> getByDatabaseConfig(
      String databaseConfigId);
  Future<rd.Result<void>> updateLastRun(
      String id, DateTime lastRunAt, DateTime? nextRunAt);
}

