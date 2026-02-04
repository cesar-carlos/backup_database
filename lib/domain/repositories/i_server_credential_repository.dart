import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IServerCredentialRepository {
  Future<rd.Result<List<ServerCredential>>> getAll();
  Future<rd.Result<ServerCredential>> getById(String id);
  Future<rd.Result<ServerCredential>> getByServerId(String serverId);
  Future<rd.Result<ServerCredential>> save(ServerCredential credential);
  Future<rd.Result<ServerCredential>> update(ServerCredential credential);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<ServerCredential>>> getActive();
  Future<rd.Result<void>> updateLastUsed(String id);
  Stream<List<ServerCredential>> watchAll();
}
