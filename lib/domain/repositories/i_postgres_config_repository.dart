import '../entities/postgres_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IPostgresConfigRepository {
  Future<rd.Result<List<PostgresConfig>>> getAll();
  Future<rd.Result<PostgresConfig>> getById(String id);
  Future<rd.Result<PostgresConfig>> create(PostgresConfig config);
  Future<rd.Result<PostgresConfig>> update(PostgresConfig config);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<PostgresConfig>>> getEnabled();
}

