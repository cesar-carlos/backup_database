import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:result_dart/result_dart.dart';

class BackupConfigLoader {
  BackupConfigLoader({
    required ISqlServerConfigRepository sqlServerConfigRepository,
    required ISybaseConfigRepository sybaseConfigRepository,
    required IPostgresConfigRepository postgresConfigRepository,
  }) : _sqlServerConfigRepository = sqlServerConfigRepository,
       _sybaseConfigRepository = sybaseConfigRepository,
       _postgresConfigRepository = postgresConfigRepository;

  final ISqlServerConfigRepository _sqlServerConfigRepository;
  final ISybaseConfigRepository _sybaseConfigRepository;
  final IPostgresConfigRepository _postgresConfigRepository;

  Future<Result<SqlServerConfig>> loadSqlServerConfig(String id) async {
    return _sqlServerConfigRepository.getById(id);
  }

  Future<Result<SybaseConfig>> loadSybaseConfig(String id) async {
    return _sybaseConfigRepository.getById(id);
  }

  Future<Result<PostgresConfig>> loadPostgresConfig(String id) async {
    return _postgresConfigRepository.getById(id);
  }
}
