import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/use_cases/notifications/test_email_configuration.dart';
import 'package:flutter/foundation.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider({
    required IEmailConfigRepository emailConfigRepository,
    required IEmailNotificationTargetRepository
    emailNotificationTargetRepository,
    required TestEmailConfiguration testEmailConfiguration,
  }) : _emailConfigRepository = emailConfigRepository,
       _emailNotificationTargetRepository = emailNotificationTargetRepository,
       _testEmailConfiguration = testEmailConfiguration {
    loadConfigs();
  }

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailNotificationTargetRepository _emailNotificationTargetRepository;
  final TestEmailConfiguration _testEmailConfiguration;

  List<EmailConfig> _configs = const [];
  String? _selectedConfigId;
  List<EmailNotificationTarget> _targets = const [];
  bool _isLoading = false;
  String? _error;
  bool _isTesting = false;

  List<EmailConfig> get configs => _configs;
  String? get selectedConfigId => _selectedConfigId;
  List<EmailNotificationTarget> get targets => _targets;

  EmailConfig? get selectedConfig => _findConfigById(_selectedConfigId);

  // Compatibilidade com tela antiga (single-config).
  EmailConfig? get emailConfig => selectedConfig;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTesting => _isTesting;
  bool get isConfigured => selectedConfig != null && selectedConfig!.enabled;

  Future<void> loadConfig() async {
    await loadConfigs();
  }

  Future<void> loadConfigs() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _emailConfigRepository.getAll();
      await result.fold(
        (configs) async {
          _configs = configs;

          if (_configs.isEmpty) {
            _selectedConfigId = null;
            _targets = const [];
            _error = null;
            return;
          }

          final hasSelected = _configs.any((c) => c.id == _selectedConfigId);
          if (!hasSelected) {
            _selectedConfigId = _configs.first.id;
          }

          _error = null;

          final selected = selectedConfig;
          if (selected != null) {
            await _loadTargetsByConfigId(selected.id, notify: false);
          }
        },
        (failure) async {
          final f = failure as Failure;
          _configs = const [];
          _selectedConfigId = null;
          _targets = const [];
          _error = f.message;
        },
      );
    } on Object catch (e) {
      _configs = const [];
      _selectedConfigId = null;
      _targets = const [];
      _error = 'Erro ao carregar configuracao de e-mail: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectConfig(String? configId) async {
    if (configId == _selectedConfigId) {
      return;
    }

    _selectedConfigId = configId;
    notifyListeners();

    if (configId == null) {
      _targets = const [];
      notifyListeners();
      return;
    }

    await _loadTargetsByConfigId(configId);
  }

  Future<void> _loadTargetsByConfigId(
    String configId, {
    bool notify = true,
  }) async {
    final result = await _emailNotificationTargetRepository.getByConfigId(
      configId,
    );

    result.fold(
      (targets) {
        _targets = targets;
        _error = null;
      },
      (failure) {
        final f = failure as Failure;
        _targets = const [];
        _error = f.message;
      },
    );

    if (notify) {
      notifyListeners();
    }
  }

  Future<bool> saveConfig(EmailConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final exists = _configs.any((c) => c.id == config.id);
      final result = exists
          ? await _emailConfigRepository.update(config)
          : await _emailConfigRepository.create(config);

      return result.fold(
        (savedConfig) async {
          _selectedConfigId = savedConfig.id;
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
      _error = 'Erro ao salvar configuracao: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteConfigById(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _emailConfigRepository.deleteById(id);
      return result.fold(
        (_) async {
          if (_selectedConfigId == id) {
            _selectedConfigId = null;
          }
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
      _error = 'Erro ao remover configuracao: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSelectedConfig() async {
    final selected = selectedConfig;
    if (selected == null) {
      _error = 'Nenhuma configuracao selecionada';
      notifyListeners();
      return false;
    }

    return deleteConfigById(selected.id);
  }

  Future<bool> testConfiguration([String? configId]) async {
    final config = configId == null
        ? selectedConfig
        : _findConfigById(configId);

    if (config == null) {
      _error = 'Nenhuma configuracao de e-mail definida';
      notifyListeners();
      return false;
    }

    _isTesting = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _testEmailConfiguration(config);
      return result.fold(
        (success) {
          _error = null;
          _isTesting = false;
          notifyListeners();
          return success;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isTesting = false;
          notifyListeners();
          return false;
        },
      );
    } on Object catch (e) {
      _error = 'Erro ao testar configuracao: $e';
      _isTesting = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleConfigEnabled(String configId, bool enabled) async {
    final config = _findConfigById(configId);
    if (config == null) {
      _error = 'Configuracao nao encontrada';
      notifyListeners();
      return false;
    }

    return saveConfig(config.copyWith(enabled: enabled));
  }

  // Compatibilidade com tela antiga.
  void toggleEnabled(bool enabled) {
    final config = selectedConfig;
    if (config != null) {
      toggleConfigEnabled(config.id, enabled);
    }
  }

  Future<void> loadTargets(String configId) async {
    await _loadTargetsByConfigId(configId);
  }

  Future<bool> addTarget(EmailNotificationTarget target) async {
    final result = await _emailNotificationTargetRepository.create(target);
    return result.fold(
      (saved) async {
        await _loadTargetsByConfigId(saved.emailConfigId);
        return true;
      },
      (failure) {
        final f = failure as Failure;
        _error = f.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> updateTarget(EmailNotificationTarget target) async {
    final result = await _emailNotificationTargetRepository.update(target);
    return result.fold(
      (saved) async {
        await _loadTargetsByConfigId(saved.emailConfigId);
        return true;
      },
      (failure) {
        final f = failure as Failure;
        _error = f.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> deleteTargetById(String targetId) async {
    final selected = selectedConfig;
    final result = await _emailNotificationTargetRepository.deleteById(
      targetId,
    );
    return result.fold(
      (_) async {
        if (selected != null) {
          await _loadTargetsByConfigId(selected.id);
        }
        return true;
      },
      (failure) {
        final f = failure as Failure;
        _error = f.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> toggleTargetEnabled(String targetId, bool enabled) async {
    final target = _findTargetById(targetId);
    if (target == null) {
      _error = 'Destinatario nao encontrado';
      notifyListeners();
      return false;
    }

    return updateTarget(target.copyWith(enabled: enabled));
  }

  EmailConfig? _findConfigById(String? id) {
    if (id == null) {
      return null;
    }

    for (final config in _configs) {
      if (config.id == id) {
        return config;
      }
    }

    return null;
  }

  EmailNotificationTarget? _findTargetById(String id) {
    for (final target in _targets) {
      if (target.id == id) {
        return target;
      }
    }

    return null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
