import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IDatabaseConfigRepository<T extends DatabaseConnectionConfig> {
  Future<rd.Result<List<T>>> getAll();
  Future<rd.Result<T>> getById(String id);
  Future<rd.Result<T>> create(T config);
  Future<rd.Result<T>> update(T config);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<T>>> getEnabled();
}
