import '../entities/sql_server_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class ISqlServerConfigRepository {
  Future<rd.Result<List<SqlServerConfig>>> getAll();
  Future<rd.Result<SqlServerConfig>> getById(String id);
  Future<rd.Result<SqlServerConfig>> create(SqlServerConfig config);
  Future<rd.Result<SqlServerConfig>> update(SqlServerConfig config);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<SqlServerConfig>>> getEnabled();
}
