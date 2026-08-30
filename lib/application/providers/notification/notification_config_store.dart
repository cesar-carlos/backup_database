import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:flutter/foundation.dart';

class NotificationConfigStore {
  NotificationConfigStore({
    required this._emailConfigRepository,
    required this._targetRepository,
    required this._notifyListeners,
    required this._clearError,
    required this._setErrorManual,
  });

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailNotificationTargetRepository _targetRepository;
  final VoidCallback _notifyListeners;
  final void Function() _clearError;
  final void Function(String message) _setErrorManual;

  List<EmailConfig> configs = const [];
  String? selectedConfigId;
  List<EmailNotificationTarget> targets = const [];
  final Set<String> updatingConfigIds = <String>{};

  EmailConfig? get selectedConfig => findConfigById(selectedConfigId);

  EmailConfig? findConfigById(String? id) {
    if (id == null) {
      return null;
    }
    for (final config in configs) {
      if (config.id == id) {
        return config;
      }
    }
    return null;
  }

  EmailNotificationTarget? findTargetById(String id) {
    for (final target in targets) {
      if (target.id == id) {
        return target;
      }
    }
    return null;
  }

  void replaceConfigInMemory(EmailConfig nextConfig) {
    final index = configs.indexWhere((config) => config.id == nextConfig.id);
    if (index < 0) {
      return;
    }
    configs = [
      for (var i = 0; i < configs.length; i++)
        if (i == index) nextConfig else configs[i],
    ];
  }

  void applyLoadedConfigs(List<EmailConfig> loaded) {
    configs = loaded;

    if (configs.isEmpty) {
      selectedConfigId = null;
      targets = const [];
      return;
    }

    final hasSelected = configs.any((c) => c.id == selectedConfigId);
    if (!hasSelected) {
      selectedConfigId = configs.first.id;
    }
  }

  Future<void> loadTargetsByConfigId(
    String configId, {
    bool notify = true,
  }) async {
    final result = await _targetRepository.getByConfigId(configId);

    result.fold(
      (loaded) {
        targets = loaded;
        _clearError();
      },
      (failure) {
        targets = const [];
        _setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
      },
    );

    if (notify) {
      _notifyListeners();
    }
  }

  Future<String?> primaryRecipientEmail(String configId) async {
    final config = findConfigById(configId);
    if (config != null && config.recipients.isNotEmpty) {
      final recipient = config.recipients.first.trim();
      if (recipient.isNotEmpty) {
        return recipient;
      }
    }

    final result = await _targetRepository.getByConfigId(configId);
    return result.fold(
      (loaded) {
        if (loaded.isEmpty) {
          return null;
        }
        final recipient = loaded.first.recipientEmail.trim();
        return recipient.isEmpty ? null : recipient;
      },
      (_) => null,
    );
  }

  Future<bool> addTarget(EmailNotificationTarget target) async {
    final result = await _targetRepository.create(target);
    return result.fold(
      (saved) async {
        await loadTargetsByConfigId(saved.emailConfigId);
        return true;
      },
      (failure) {
        _setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
        return false;
      },
    );
  }

  Future<bool> updateTarget(EmailNotificationTarget target) async {
    final result = await _targetRepository.update(target);
    return result.fold(
      (saved) async {
        await loadTargetsByConfigId(saved.emailConfigId);
        return true;
      },
      (failure) {
        _setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
        return false;
      },
    );
  }

  Future<bool> deleteTargetById(String targetId) async {
    final selected = selectedConfig;
    final result = await _targetRepository.deleteById(targetId);
    return result.fold(
      (_) async {
        if (selected != null) {
          await loadTargetsByConfigId(selected.id);
        }
        return true;
      },
      (failure) {
        _setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
        return false;
      },
    );
  }

  Future<bool> toggleTargetEnabled(String targetId, bool enabled) async {
    final target = findTargetById(targetId);
    if (target == null) {
      _setErrorManual('Destinatário não encontrado');
      return false;
    }

    return updateTarget(target.copyWith(enabled: enabled));
  }

  Future<bool> toggleConfigEnabled(String configId, bool enabled) async {
    if (updatingConfigIds.contains(configId)) {
      return false;
    }

    final config = findConfigById(configId);
    if (config == null) {
      _setErrorManual('Configuração não encontrada');
      return false;
    }

    final previousConfig = config;
    final optimisticConfig = config.copyWith(enabled: enabled);
    replaceConfigInMemory(optimisticConfig);
    updatingConfigIds.add(configId);
    _clearError();
    _notifyListeners();

    try {
      final result = await _emailConfigRepository.save(optimisticConfig);

      return result.fold(
        (_) {
          _clearError();
          return true;
        },
        (failure) {
          replaceConfigInMemory(previousConfig);
          _setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
          return false;
        },
      );
    } on Object catch (e) {
      replaceConfigInMemory(previousConfig);
      _setErrorManual(
        'Erro ao atualizar status da configuração: '
        '${AsyncStateMixin.extractFailureMessage(e)}',
      );
      return false;
    } finally {
      updatingConfigIds.remove(configId);
      _notifyListeners();
    }
  }
}
