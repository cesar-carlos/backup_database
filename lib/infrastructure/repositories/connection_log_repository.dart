import 'package:backup_database/domain/entities/connection_log.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ConnectionLogRepository implements IConnectionLogRepository {
  ConnectionLogRepository(this._database);

  final AppDatabase _database;

  @override
  Future<rd.Result<List<ConnectionLog>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar log de conexões',
      action: () async {
        final list = await _database.connectionLogDao.getAll();
        return list.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<ConnectionLog>>> getRecentLogs(int limit) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar log de conexões',
      action: () async {
        final list = await _database.connectionLogDao.getRecentLogs(limit);
        return list.map(_toEntity).toList();
      },
    );
  }

  @override
  Stream<List<ConnectionLog>> watchAll() {
    return _database.connectionLogDao.watchAll().map(
      (list) => list.map(_toEntity).toList(),
    );
  }

  @override
  Future<rd.Result<void>> insertAttempt({
    required String clientHost,
    required bool success,
    String? serverId,
    String? errorMessage,
    String? clientId,
  }) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao registrar log de conexão',
      action: () => _database.connectionLogDao.insertConnectionAttempt(
        clientHost: clientHost,
        success: success,
        serverId: serverId,
        errorMessage: errorMessage,
        clientId: clientId,
      ),
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
