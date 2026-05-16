import 'package:backup_database/application/providers/database_config_provider_base.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';

class PostgresConfigProvider
    extends DatabaseConfigProviderBase<PostgresConfig> {
  PostgresConfigProvider(
    IPostgresConfigRepository repository,
    IScheduleRepository scheduleRepository,
  ) : super(
        repository: repository,
        scheduleRepository: scheduleRepository,
      );

  @override
  PostgresConfig duplicateConfigCopy(PostgresConfig source) {
    return PostgresConfig(
      name: '${source.name} (cópia)',
      host: source.host,
      database: source.database,
      username: source.username,
      password: source.password,
      port: source.port,
      enabled: source.enabled,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  PostgresConfig withEnabled(PostgresConfig config, bool enabled) =>
      config.copyWith(enabled: enabled);
}
