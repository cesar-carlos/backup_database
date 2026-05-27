import 'package:backup_database/application/providers/database_config_provider_base.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';

class PostgresConfigProvider
    extends DatabaseConfigProviderBase<PostgresConfig> {
  PostgresConfigProvider(
    IPostgresConfigRepository repository,
    IScheduleRepository scheduleRepository,
    this._toolVerificationService,
  ) : super(
        repository: repository,
        scheduleRepository: scheduleRepository,
      );

  final ToolVerificationService _toolVerificationService;

  @override
  Future<void> verifyToolsOrThrow() async {
    final result = await _toolVerificationService.verifyPostgresTools();
    result.fold((_) {}, (failure) => throw failure);
  }

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
