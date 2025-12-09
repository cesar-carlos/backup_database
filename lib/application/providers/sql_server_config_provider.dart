import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/sql_server_config.dart';
import '../../domain/repositories/i_sql_server_config_repository.dart';

class SqlServerConfigProvider extends ChangeNotifier {
  final ISqlServerConfigRepository _repository;

  List<SqlServerConfig> _configs = [];
  bool _isLoading = false;
  String? _error;

  SqlServerConfigProvider(this._repository) {
    loadConfigs();
  }

  List<SqlServerConfig> get configs => _configs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<SqlServerConfig> get activeConfigs =>
      _configs.where((c) => c.enabled).toList();

  List<SqlServerConfig> get inactiveConfigs =>
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

  Future<bool> createConfig(SqlServerConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.create(config);
      return result.fold(
        (_) async {
          // Recarrega do banco para garantir dados corretos
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

  Future<bool> updateConfig(SqlServerConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.update(config);
      return result.fold(
        (_) async {
          // Recarrega do banco para garantir dados corretos
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

  Future<bool> duplicateConfig(SqlServerConfig source) async {
    // Cria nova instância com novo ID (gerado no construtor) e nome indicando cópia
    final copy = SqlServerConfig(
      name: '${source.name} (cópia)',
      server: source.server,
      database: source.database,
      username: source.username,
      password: source.password,
      port: source.port,
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

  SqlServerConfig? getConfigById(String id) {
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
