import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';
import 'package:flutter/foundation.dart';

class SqlServerConfigProvider extends ChangeNotifier with AsyncStateMixin {
  SqlServerConfigProvider(
    this._repository,
    this._scheduleRepository,
    this._toolVerificationService,
  ) {
    loadConfigs();
  }
  final ISqlServerConfigRepository _repository;
  final IScheduleRepository _scheduleRepository;
  final ToolVerificationService _toolVerificationService;

  List<SqlServerConfig> _configs = [];

  List<SqlServerConfig> get configs => _configs;

  List<SqlServerConfig> get activeConfigs =>
      _configs.where((c) => c.enabled).toList();

  List<SqlServerConfig> get inactiveConfigs =>
      _configs.where((c) => !c.enabled).toList();

  Future<void> loadConfigs() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao carregar configurações',
      action: () async {
        final result = await _repository.getAll();
        result.fold(
          (configs) => _configs = configs,
          (failure) => throw failure,
        );
      },
    );
  }

  Future<bool> createConfig(SqlServerConfig config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao criar configuração',
      action: () async {
        await _verifySqlCmdOrThrow();
        final result = await _repository.create(config);
        return result.fold(
          (_) async {
            await _reloadConfigs();
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> updateConfig(SqlServerConfig config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao atualizar configuração',
      action: () async {
        await _verifySqlCmdOrThrow();
        final result = await _repository.update(config);
        return result.fold(
          (_) async {
            await _reloadConfigs();
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> deleteConfig(String id) async {
    // Validações sincrônas antes do `runAsync` (não precisam do
    // contador de loading — são checagens rápidas).
    final schedulesResult = await _scheduleRepository.getByDatabaseConfig(id);
    if (schedulesResult.isError()) {
      final failure = schedulesResult.exceptionOrNull();
      setErrorManual(
        failure is Failure
            ? 'Não foi possível validar dependências: ${failure.message}'
            : 'Não foi possível validar dependências antes da exclusão.',
      );
      return false;
    }

    final linkedSchedules = schedulesResult.getOrNull() ?? [];
    if (linkedSchedules.isNotEmpty) {
      setErrorManual(
        'Há agendamentos vinculados a esta configuração. '
        'Remova-os antes de excluir.',
      );
      return false;
    }

    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao deletar configuração',
      action: () async {
        final result = await _repository.delete(id);
        return result.fold(
          (_) {
            // P9 fix: reassign em vez de mutação in-place. Listeners
            // que comparam por `identical()` agora detectam a mudança.
            _configs = _configs.where((c) => c.id != id).toList();
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> duplicateConfig(SqlServerConfig source) async {
    final copy = SqlServerConfig(
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
    return createConfig(copy);
  }

  Future<bool> toggleEnabled(String id, bool enabled) async {
    final config = getConfigById(id);
    if (config == null) {
      setErrorManual('Configuração não encontrada.');
      return false;
    }
    return updateConfig(config.copyWith(enabled: enabled));
  }

  /// P6 fix: usa pattern declarativo `firstWhereOrNull` em vez do
  /// idiom `try { firstWhere }` que era usado antes.
  SqlServerConfig? getConfigById(String id) {
    for (final c in _configs) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Verifica disponibilidade do `sqlcmd` no sistema. Lança a `Failure`
  /// retornada pelo verificador para que o `runAsync` capture e
  /// propague a mensagem para `_error`. Antes, o controle de fluxo era
  /// feito por boolean + side-effect dentro do `fold`, resultando em
  /// código difícil de seguir (P8).
  Future<void> _verifySqlCmdOrThrow() async {
    final result = await _toolVerificationService.verifySqlCmd();
    result.fold((_) {}, (failure) {
      throw failure;
    });
  }

  /// Recarrega configs sem disparar nova reentrância no `runAsync`
  /// (estamos dentro de um). Faz a leitura direta e atualiza o estado.
  Future<void> _reloadConfigs() async {
    final result = await _repository.getAll();
    result.fold(
      (configs) => _configs = configs,
      (failure) => throw failure,
    );
  }
}
