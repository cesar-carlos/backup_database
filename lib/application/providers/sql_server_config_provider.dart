import 'package:backup_database/application/providers/database_config_provider_base.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';

class SqlServerConfigProvider
    extends DatabaseConfigProviderBase<SqlServerConfig> {
  SqlServerConfigProvider(
    ISqlServerConfigRepository repository,
    IScheduleRepository scheduleRepository,
    this._toolVerificationService,
  ) : super(
        repository: repository,
        scheduleRepository: scheduleRepository,
      );

  final ToolVerificationService _toolVerificationService;

  @override
  Future<void> verifyToolsOrThrow() async {
    final result = await _toolVerificationService.verifySqlCmd();
    result.fold((_) {}, (failure) => throw failure);
  }

  @override
  SqlServerConfig duplicateConfigCopy(SqlServerConfig source) {
    return SqlServerConfig(
      name: '${source.name} (cópia)',
      server: source.server,
      database: source.database,
      username: source.username,
      password: source.password,
      port: source.port,
      enabled: source.enabled,
      useWindowsAuth: source.useWindowsAuth,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  SqlServerConfig withEnabled(SqlServerConfig config, bool enabled) =>
      config.copyWith(enabled: enabled);
}
