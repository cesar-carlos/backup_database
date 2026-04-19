import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:flutter/foundation.dart';

class PostgresConfigProvider extends ChangeNotifier with AsyncStateMixin {
  PostgresConfigProvider(
    this._repository,
    this._scheduleRepository,
  ) {
    loadConfigs();
  }
  final IPostgresConfigRepository _repository;
  final IScheduleRepository _scheduleRepository;

  List<PostgresConfig> _configs = [];

  List<PostgresConfig> get configs => _configs;

  List<PostgresConfig> get activeConfigs =>
      _configs.where((c) => c.enabled).toList();

  List<PostgresConfig> get inactiveConfigs =>
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

  Future<bool> createConfig(PostgresConfig config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao criar configuração',
      action: () async {
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

  Future<bool> updateConfig(PostgresConfig config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao atualizar configuração',
      action: () async {
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
            _configs = _configs.where((c) => c.id != id).toList();
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> duplicateConfig(PostgresConfig source) async {
    final copy = PostgresConfig(
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

  PostgresConfig? getConfigById(String id) {
    for (final c in _configs) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _reloadConfigs() async {
    final result = await _repository.getAll();
    result.fold(
      (configs) => _configs = configs,
      (failure) => throw failure,
    );
  }
}
