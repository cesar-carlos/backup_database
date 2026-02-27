import 'dart:async';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';
import 'package:flutter/foundation.dart';

class SybaseConfigProvider extends ChangeNotifier {
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
  bool _isLoading = false;
  String? _error;
  SybaseToolsStatus? _toolsStatus;
  bool _isLoadingTools = false;

  List<SybaseConfig> get configs => _configs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  SybaseToolsStatus? get toolsStatus => _toolsStatus;
  bool get isLoadingTools => _isLoadingTools;

  List<SybaseConfig> get activeConfigs =>
      _configs.where((c) => c.enabled).toList();

  List<SybaseConfig> get inactiveConfigs =>
      _configs.where((c) => !c.enabled).toList();

  Future<void> refreshToolsStatus() async {
    _isLoadingTools = true;
    notifyListeners();

    try {
      final result = await _toolVerificationService.verifySybaseToolsDetailed();
      result.fold(
        (status) {
          _toolsStatus = status;
        },
        (_) {
          _toolsStatus = null;
        },
      );
    } on Object catch (_) {
      _toolsStatus = null;
    } finally {
      _isLoadingTools = false;
      notifyListeners();
    }
  }

  Future<void> loadConfigs() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      unawaited(refreshToolsStatus());

      final result = await _repository.getAll();
      result.fold(
        (configs) {
          _configs = configs;
          _error = null;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao carregar configurações: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createConfig(SybaseConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final toolVerificationResult = await _toolVerificationService
          .verifySybaseTools();
      final toolVerification = toolVerificationResult.fold(
        (_) => true,
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );

      if (!toolVerification) {
        return false;
      }

      final result = await _repository.create(config);
      return result.fold(
        (_) async {
          await loadConfigs();
          return true;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao criar configuração: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateConfig(SybaseConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final toolVerificationResult = await _toolVerificationService
          .verifySybaseTools();
      final toolVerification = toolVerificationResult.fold(
        (_) => true,
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );

      if (!toolVerification) {
        return false;
      }

      final result = await _repository.update(config);
      return result.fold(
        (_) async {
          await loadConfigs();
          return true;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao atualizar configuração: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteConfig(String id) async {
    final schedulesResult = await _scheduleRepository.getByDatabaseConfig(id);
    if (schedulesResult.isError()) {
      final failure = schedulesResult.exceptionOrNull();
      _error = failure is Failure
          ? 'Não foi possível validar dependências: ${failure.message}'
          : 'Não foi possível validar dependências antes da exclusão.';
      notifyListeners();
      return false;
    }

    final linkedSchedules = schedulesResult.getOrNull() ?? [];
    if (linkedSchedules.isNotEmpty) {
      _error =
          'Há agendamentos vinculados a esta configuração Sybase. '
          'Remova-os antes de excluir.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.delete(id);
      return result.fold(
        (_) {
          _configs.removeWhere((c) => c.id == id);
          _error = null;
          _isLoading = false;
          notifyListeners();
          return true;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao deletar configuração: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
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
    final config = _configs.firstWhere((c) => c.id == id);
    return updateConfig(config.copyWith(enabled: enabled));
  }

  SybaseConfig? getConfigById(String id) {
    try {
      return _configs.firstWhere((c) => c.id == id);
    } on Object catch (e) {
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
