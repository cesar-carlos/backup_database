import 'package:backup_database/application/providers/database_config_provider_base.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/repositories/i_firebird_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';

class FirebirdConfigProvider
    extends DatabaseConfigProviderBase<FirebirdConfig> {
  FirebirdConfigProvider(
    IFirebirdConfigRepository repository,
    IScheduleRepository scheduleRepository,
    this._toolVerificationService,
  ) : super(
        repository: repository,
        scheduleRepository: scheduleRepository,
      );

  final ToolVerificationService _toolVerificationService;

  @override
  Future<void> verifyToolsOrThrow() async {
    final result = await _toolVerificationService.verifyFirebirdCliTools();
    result.fold((_) {}, (failure) => throw failure);
  }

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
