import 'package:backup_database/domain/entities/connection_log.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IConnectionLogRepository {
  Future<rd.Result<List<ConnectionLog>>> getAll();
  Future<rd.Result<List<ConnectionLog>>> getRecentLogs(int limit);
  Stream<List<ConnectionLog>> watchAll();
}
