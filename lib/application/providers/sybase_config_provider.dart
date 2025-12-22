import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/sybase_config.dart';
import '../../domain/repositories/i_sybase_config_repository.dart';
import '../../domain/repositories/i_schedule_repository.dart';
import '../../infrastructure/external/process/tool_verification_service.dart';

class SybaseConfigProvider extends ChangeNotifier {
  final ISybaseConfigRepository _repository;
  final IScheduleRepository _scheduleRepository;
  final ToolVerificationService _toolVerificationService;

  List<SybaseConfig> _configs = [];
  bool _isLoading = false;
  String? _error;

  SybaseConfigProvider(
    this._repository,
    this._scheduleRepository,
    this._toolVerificationService,
  ) {
    loadConfigs();
  }

  List<SybaseConfig> get configs => _configs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<SybaseConfig> get activeConfigs =>
      _configs.where((c) => c.enabled).toList();

  List<SybaseConfig> get inactiveConfigs =>
      _configs.where((c) => !c.enabled).toList();

  Future<void> loadConfigs() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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
    } catch (e) {
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
      final toolVerificationResult =
          await _toolVerificationService.verifySybaseTools();
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
    } catch (e) {
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
      final toolVerificationResult =
          await _toolVerificationService.verifySybaseTools();
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
    } catch (e) {
      _error = 'Erro ao atualizar configuração: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteConfig(String id) async {
    final schedulesResult = await _scheduleRepository.getByDatabaseConfig(id);
    if (schedulesResult.isSuccess() && schedulesResult.getOrNull()!.isNotEmpty) {
      _error =
          'Há agendamentos vinculados a esta configuração Sybase. Remova-os antes de excluir.';
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
    } catch (e) {
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
    return await createConfig(copy);
  }

  Future<bool> toggleEnabled(String id, bool enabled) async {
    final config = _configs.firstWhere((c) => c.id == id);
    return await updateConfig(config.copyWith(enabled: enabled));
  }

  SybaseConfig? getConfigById(String id) {
    try {
      return _configs.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

