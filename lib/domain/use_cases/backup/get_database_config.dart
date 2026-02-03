import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:result_dart/result_dart.dart';

/// Use case for retrieving database configuration based on database type.
///
/// Centralizes the logic for fetching configuration from the appropriate
/// repository based on the [DatabaseType]. This eliminates code duplication
/// across the codebase.
class GetDatabaseConfig {
  const GetDatabaseConfig({
    required ISqlServerConfigRepository sqlServerConfigRepository,
    required ISybaseConfigRepository sybaseConfigRepository,
    required IPostgresConfigRepository postgresConfigRepository,
  }) : _sqlServerConfigRepository = sqlServerConfigRepository,
       _sybaseConfigRepository = sybaseConfigRepository,
       _postgresConfigRepository = postgresConfigRepository;

  final ISqlServerConfigRepository _sqlServerConfigRepository;
  final ISybaseConfigRepository _sybaseConfigRepository;
  final IPostgresConfigRepository _postgresConfigRepository;

  /// Retrieves the database configuration for the given [configId] and [type].
  ///
  /// Returns a [Result] containing the configuration object (SqlServerConfig,
  /// SybaseConfig, or PostgresConfig) or a [Failure] if the configuration
  /// is not found or an error occurs.
  ///
  /// The caller is responsible for casting the result to the appropriate type
  /// based on the [DatabaseType] used.
  Future<Result<Object>> call(String configId, DatabaseType type) async {
    switch (type) {
      case DatabaseType.sqlServer:
        final result = await _sqlServerConfigRepository.getById(configId);
        return result.map((config) => config as Object);

      case DatabaseType.sybase:
        final result = await _sybaseConfigRepository.getById(configId);
        return result.map((config) => config as Object);

      case DatabaseType.postgresql:
        final result = await _postgresConfigRepository.getById(configId);
        return result.map((config) => config as Object);
    }
  }
}
