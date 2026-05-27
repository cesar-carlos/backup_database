import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/application/providers/database_connection_test_snapshot.dart';
import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_database_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:flutter/foundation.dart';

abstract class DatabaseConfigProviderBase<T extends DatabaseConnectionConfig>
    extends ChangeNotifier
    with AsyncStateMixin {
  DatabaseConfigProviderBase({
    required IDatabaseConfigRepository<T> repository,
    required IScheduleRepository scheduleRepository,
  }) : _repository = repository,
       _scheduleRepository = scheduleRepository {
    unawaited(loadConfigs());
  }

  final IDatabaseConfigRepository<T> _repository;
  final IScheduleRepository _scheduleRepository;

  List<T> _configs = [];

  Map<String, DatabaseConnectionTestSnapshot> _connectionTestsByConfigId =
      <String, DatabaseConnectionTestSnapshot>{};

  List<T> get configs => _configs;

  DatabaseConnectionTestSnapshot? connectionTestSnapshotFor(String configId) =>
      _connectionTestsByConfigId[configId];

  void recordConnectionTest(String configId, {required bool success}) {
    _connectionTestsByConfigId =
        Map<String, DatabaseConnectionTestSnapshot>.from(
          _connectionTestsByConfigId,
        )..[configId] = (testedAt: DateTime.now(), success: success);
    notifyListeners();
  }

  void _forgetConnectionTest(String configId) {
    if (!_connectionTestsByConfigId.containsKey(configId)) {
      return;
    }
    _connectionTestsByConfigId =
        Map<String, DatabaseConnectionTestSnapshot>.from(
          _connectionTestsByConfigId,
        )..remove(configId);
    notifyListeners();
  }

  List<T> get activeConfigs => _configs.where((c) => c.enabled).toList();

  List<T> get inactiveConfigs => _configs.where((c) => !c.enabled).toList();

  Future<void> verifyToolsOrThrow() async {}

  T duplicateConfigCopy(T source);

  T withEnabled(T config, bool enabled);

  String get configNotFoundMessage => 'Configuração não encontrada.';

  String get linkedSchedulesDeleteError =>
      'Há agendamentos vinculados a esta configuração. '
      'Remova-os antes de excluir.';

  Future<void> loadConfigs() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao carregar configurações',
      action: () async {
        final result = await _repository.getAll();
        result.fold(
          (list) => _configs = list,
          (failure) => throw failure,
        );
      },
    );
  }

  Future<bool> createConfig(T config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao criar configuração',
      action: () async {
        await verifyToolsOrThrow();
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

  Future<bool> updateConfig(T config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao atualizar configuração',
      action: () async {
        await verifyToolsOrThrow();
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
    if (ok ?? false) {
      _forgetConnectionTest(config.id);
    }
    return ok ?? false;
  }

  Future<bool> deleteConfig(String id) async {
    // Delega para `AsyncStateMixin.checkNoLinkedDependencies` que
    // consolida o pattern de validação de dependências também usado
    // em `DestinationProvider.deleteDestination`.
    final canDelete = await checkNoLinkedDependencies<Schedule>(
      dependencyCheck: () => _scheduleRepository.getByDatabaseConfig(id),
      dependencyErrorMessage: linkedSchedulesDeleteError,
    );
    if (!canDelete) return false;

    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao deletar configuração',
      action: () async {
        final result = await _repository.delete(id);
        return result.fold(
          (_) {
            _configs = _configs.where((c) => c.id != id).toList();
            _forgetConnectionTest(id);
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> duplicateConfig(T source) async {
    return createConfig(duplicateConfigCopy(source));
  }

  Future<bool> toggleEnabled(String id, bool enabled) async {
    final config = getConfigById(id);
    if (config == null) {
      setErrorManual(configNotFoundMessage);
      return false;
    }
    return updateConfig(withEnabled(config, enabled));
  }

  T? getConfigById(String id) {
    for (final c in _configs) {
      if (c.id == id) {
        return c;
      }
    }
    return null;
  }

  Future<void> _reloadConfigs() async {
    final result = await _repository.getAll();
    result.fold(
      (list) => _configs = list,
      (failure) => throw failure,
    );
  }
}
