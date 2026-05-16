import 'dart:async';

import 'package:backup_database/application/providers/database_config_provider_base.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';

class SybaseConfigProvider extends DatabaseConfigProviderBase<SybaseConfig> {
  SybaseConfigProvider(
    ISybaseConfigRepository repository,
    IScheduleRepository scheduleRepository,
    this._toolVerificationService,
  ) : super(
        repository: repository,
        scheduleRepository: scheduleRepository,
      );

  final ToolVerificationService _toolVerificationService;

  SybaseToolsStatus? _toolsStatus;
  bool _isLoadingTools = false;

  SybaseToolsStatus? get toolsStatus => _toolsStatus;

  bool get isLoadingTools => _isLoadingTools;

  @override
  String get configNotFoundMessage => 'Configuração Sybase não encontrada.';

  @override
  String get linkedSchedulesDeleteError =>
      'Há agendamentos vinculados a esta configuração Sybase. '
      'Remova-os antes de excluir.';

  Future<void> refreshToolsStatus() async {
    _isLoadingTools = true;
    notifyListeners();

    try {
      final result = await _toolVerificationService.verifySybaseToolsDetailed();
      result.fold(
        (status) => _toolsStatus = status,
        (_) => _toolsStatus = null,
      );
    } on Object catch (_) {
      _toolsStatus = null;
    } finally {
      _isLoadingTools = false;
      notifyListeners();
    }
  }

  @override
  Future<void> loadConfigs() async {
    unawaited(refreshToolsStatus());
    await super.loadConfigs();
  }

  @override
  Future<void> verifyToolsOrThrow() async {
    final result = await _toolVerificationService.verifySybaseTools();
    result.fold((_) {}, (failure) => throw failure);
  }

  @override
  SybaseConfig duplicateConfigCopy(SybaseConfig source) {
    return SybaseConfig(
      name: '${source.name} (cópia)',
      serverName: source.serverName,
      databaseName: source.databaseName,
      databaseFile: source.databaseFile,
      port: source.port,
      username: source.username,
      password: source.password,
      enabled: source.enabled,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  SybaseConfig withEnabled(SybaseConfig config, bool enabled) =>
      config.copyWith(enabled: enabled);
}
