import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';
import 'package:flutter/foundation.dart';

class SybaseConfigProvider extends ChangeNotifier with AsyncStateMixin {
  SybaseConfigProvider(
    this._repository,
    this._scheduleRepository,
    this._toolVerificationService,
  ) {
    loadConfigs();
  }
  final ISybaseConfigRepository _repository;
  final IScheduleRepository _scheduleRepository;
  final ToolVerificationService _toolVerificationService;

  List<SybaseConfig> _configs = [];
  SybaseToolsStatus? _toolsStatus;
  bool _isLoadingTools = false;

  List<SybaseConfig> get configs => _configs;
  SybaseToolsStatus? get toolsStatus => _toolsStatus;
  bool get isLoadingTools => _isLoadingTools;

  List<SybaseConfig> get activeConfigs =>
      _configs.where((c) => c.enabled).toList();

  List<SybaseConfig> get inactiveConfigs =>
      _configs.where((c) => !c.enabled).toList();

  /// Atualiza o status das ferramentas Sybase. Usa um indicador
  /// dedicado (`isLoadingTools`) em vez do `isLoading` global porque a
  /// UI exibe estes dois estados separadamente.
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

  Future<void> loadConfigs() async {
    // Dispara o refresh em paralelo (fire-and-forget) para não
    // bloquear a tela com a checagem de tools.
    unawaited(refreshToolsStatus());

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

  Future<bool> createConfig(SybaseConfig config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao criar configuração',
      action: () async {
        await _verifyToolsOrThrow();
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

  Future<bool> updateConfig(SybaseConfig config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao atualizar configuração',
      action: () async {
        await _verifyToolsOrThrow();
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
        'Há agendamentos vinculados a esta configuração Sybase. '
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

  Future<bool> duplicateConfig(SybaseConfig source) async {
    final copy = SybaseConfig(
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
    return createConfig(copy);
  }

  Future<bool> toggleEnabled(String id, bool enabled) async {
    final config = getConfigById(id);
    if (config == null) {
      setErrorManual('Configuração Sybase não encontrada.');
      return false;
    }
    return updateConfig(config.copyWith(enabled: enabled));
  }

  SybaseConfig? getConfigById(String id) {
    for (final c in _configs) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _verifyToolsOrThrow() async {
    final result = await _toolVerificationService.verifySybaseTools();
    result.fold((_) {}, (failure) => throw failure);
  }

  Future<void> _reloadConfigs() async {
    final result = await _repository.getAll();
    result.fold(
      (configs) => _configs = configs,
      (failure) => throw failure,
    );
  }
}
