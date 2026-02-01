import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/connection_log.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ConnectionLogRepository implements IConnectionLogRepository {
  ConnectionLogRepository(this._database);

  final AppDatabase _database;

  @override
  Future<rd.Result<List<ConnectionLog>>> getAll() async {
    try {
      final list = await _database.connectionLogDao.getAll();
      return rd.Success(list.map(_toEntity).toList());
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar log de conexões: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<ConnectionLog>>> getRecentLogs(int limit) async {
    try {
      final list = await _database.connectionLogDao.getRecentLogs(limit);
      return rd.Success(list.map(_toEntity).toList());
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar log de conexões: $e'),
      );
    }
  }

  @override
  Stream<List<ConnectionLog>> watchAll() {
    return _database.connectionLogDao.watchAll().map(
          (list) => list.map(_toEntity).toList(),
        );
  }

  ConnectionLog _toEntity(ConnectionLogsTableData data) {
    return ConnectionLog(
      id: data.id,
      clientHost: data.clientHost,
      serverId: data.serverId,
      success: data.success,
      errorMessage: data.errorMessage,
      timestamp: data.timestamp,
      clientId: data.clientId,
    );
  }
}
