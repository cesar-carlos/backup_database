import 'package:backup_database/application/providers/database_config_provider_base.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/repositories/i_firebird_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';

class FirebirdConfigProvider
    extends DatabaseConfigProviderBase<FirebirdConfig> {
  FirebirdConfigProvider(
    IFirebirdConfigRepository repository,
    IScheduleRepository scheduleRepository,
  ) : super(
        repository: repository,
        scheduleRepository: scheduleRepository,
      );

  @override
  FirebirdConfig duplicateConfigCopy(FirebirdConfig source) {
    return FirebirdConfig(
      name: '${source.name} (cópia)',
      host: source.host,
      databaseFile: source.databaseFile,
      username: source.username,
      password: source.password,
      port: source.port,
      aliasName: source.aliasName,
      useEmbedded: source.useEmbedded,
      clientLibraryPath: source.clientLibraryPath,
      serverVersionHint: source.serverVersionHint,
      serviceManagerMode: source.serviceManagerMode,
      cryptKey: source.cryptKey,
      enabled: source.enabled,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  FirebirdConfig withEnabled(FirebirdConfig config, bool enabled) =>
      config.copyWith(enabled: enabled);
}
