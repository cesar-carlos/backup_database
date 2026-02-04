import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IServerConnectionRepository {
  Future<rd.Result<List<ServerConnection>>> getAll();
  Future<rd.Result<ServerConnection>> getById(String id);
  Future<rd.Result<ServerConnection>> save(ServerConnection connection);
  Future<rd.Result<ServerConnection>> update(ServerConnection connection);
  Future<rd.Result<void>> delete(String id);
  Stream<List<ServerConnection>> watchAll();
}
