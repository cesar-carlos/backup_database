import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:flutter/foundation.dart';

class PostgresConfigProvider extends ChangeNotifier {
  PostgresConfigProvider(
    this._repository,
    this._scheduleRepository,
  ) {
    loadConfigs();
  }
  final IPostgresConfigRepository _repository;
  final IScheduleRepository _scheduleRepository;

  List<PostgresConfig> _configs = [];
  bool _isLoading = false;
  String? _error;

  List<PostgresConfig> get configs => _configs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<PostgresConfig> get activeConfigs =>
      _configs.where((c) => c.enabled).toList();

  List<PostgresConfig> get inactiveConfigs =>
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
    } on Object catch (e) {
      _error = 'Erro ao carregar configurações: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createConfig(PostgresConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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

  Future<bool> updateConfig(PostgresConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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
          'Há agendamentos vinculados a esta configuração. '
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

  Future<bool> duplicateConfig(PostgresConfig source) async {
    final copy = PostgresConfig(
      name: '${source.name} (cópia)',
      host: source.host,
      port: source.port,
      database: source.database,
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

  PostgresConfig? getConfigById(String id) {
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
