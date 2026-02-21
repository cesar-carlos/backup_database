import 'dart:async';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:backup_database/domain/services/i_oauth_smtp_service.dart';
import 'package:backup_database/domain/use_cases/notifications/test_email_configuration.dart';
import 'package:flutter/foundation.dart';

enum NotificationHistoryPeriod {
  last24Hours,
  last7Days,
  last30Days,
  all,
}

class NotificationProvider extends ChangeNotifier {
  NotificationProvider({
    required IEmailConfigRepository emailConfigRepository,
    required IEmailNotificationTargetRepository
    emailNotificationTargetRepository,
    required IEmailTestAuditRepository emailTestAuditRepository,
    required IOAuthSmtpService oauthSmtpService,
    required TestEmailConfiguration testEmailConfiguration,
  }) : _emailConfigRepository = emailConfigRepository,
       _emailNotificationTargetRepository = emailNotificationTargetRepository,
       _emailTestAuditRepository = emailTestAuditRepository,
       _oauthSmtpService = oauthSmtpService,
       _testEmailConfiguration = testEmailConfiguration {
    loadConfigs();
  }

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailNotificationTargetRepository _emailNotificationTargetRepository;
  final IEmailTestAuditRepository _emailTestAuditRepository;
  final IOAuthSmtpService _oauthSmtpService;
  final TestEmailConfiguration _testEmailConfiguration;

  List<EmailConfig> _configs = const [];
  String? _selectedConfigId;
  List<EmailNotificationTarget> _targets = const [];
  bool _isLoading = false;
  String? _error;
  bool _isTesting = false;
  String? _testingConfigId;
  final Set<String> _testingConfigIds = <String>{};
  List<EmailTestAudit> _testHistory = const [];
  String? _historyError;
  bool _isHistoryLoading = false;
  NotificationHistoryPeriod _historyPeriod =
      NotificationHistoryPeriod.last7Days;
  String? _historyConfigIdFilter;
  Timer? _historyReloadTimer;

  List<EmailConfig> get configs => _configs;
  String? get selectedConfigId => _selectedConfigId;
  List<EmailNotificationTarget> get targets => _targets;

  EmailConfig? get selectedConfig => _findConfigById(_selectedConfigId);

  // Compatibilidade com tela antiga (single-config).
  EmailConfig? get emailConfig => selectedConfig;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<EmailTestAudit> get testHistory => _testHistory;
  String? get historyError => _historyError;
  bool get isHistoryLoading => _isHistoryLoading;
  NotificationHistoryPeriod get historyPeriod => _historyPeriod;
  String? get historyConfigIdFilter => _historyConfigIdFilter;
  bool get isTesting => _isTesting;
  String? get testingConfigId => _testingConfigId;
  bool get isConfigured => selectedConfig != null && selectedConfig!.enabled;
  bool isConfigUnderTest(String configId) =>
      _testingConfigIds.contains(configId);

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
            _testHistory = const [];
            _historyConfigIdFilter = null;
            _historyError = null;
            _error = null;
            return;
          }

          final hasSelected = _configs.any((c) => c.id == _selectedConfigId);
          if (!hasSelected) {
            _selectedConfigId = _configs.first.id;
          }
          _historyConfigIdFilter ??= _selectedConfigId;
          final hasHistoryFilter = _configs.any(
            (c) => c.id == _historyConfigIdFilter,
          );
          if (!hasHistoryFilter) {
            _historyConfigIdFilter = _selectedConfigId;
          }

          _error = null;

          final selected = selectedConfig;
          if (selected != null) {
            await _loadTargetsByConfigId(selected.id, notify: false);
          }
          await _loadTestHistory(notify: false);
        },
        (failure) async {
          final f = failure as Failure;
          _configs = const [];
          _selectedConfigId = null;
          _targets = const [];
          _testHistory = const [];
          _historyConfigIdFilter = null;
          _historyError = null;
          _error = f.message;
        },
      );
    } on Object catch (e) {
      _configs = const [];
      _selectedConfigId = null;
      _targets = const [];
      _testHistory = const [];
      _historyConfigIdFilter = null;
      _historyError = null;
      _error = 'Erro ao carregar configuração de e-mail: $e';
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
    _historyConfigIdFilter = configId;
    notifyListeners();

    if (configId == null) {
      _targets = const [];
      _testHistory = const [];
      notifyListeners();
      return;
    }

    await _loadTargetsByConfigId(configId);
    await _loadTestHistory();
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
      final recipient = await _resolvePrimaryRecipient(config);
      if (recipient == null) {
        _error = 'Informe ao menos um e-mail destinatário na configuração SMTP';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final configToSave = config.copyWith(recipients: [recipient]);
      final result = await _emailConfigRepository.saveWithPrimaryTarget(
        config: configToSave,
        primaryRecipientEmail: recipient,
      );

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
      _error = 'Nenhuma configuração de e-mail definida';
      notifyListeners();
      return false;
    }

    if (!_beginTesting(config.id)) {
      return false;
    }

    try {
      final result = await _testEmailConfiguration(config);
      return result.fold(
        (success) {
          _error = null;
          return success;
        },
        (failure) {
          final f = failure as Failure;
          _error = _formatTestErrorMessage(f.message);
          return false;
        },
      );
    } on Object catch (e) {
      _error = _formatTestErrorMessage('Erro ao testar configuracao: $e');
      return false;
    } finally {
      _endTesting(config.id);
      _scheduleHistoryReload();
    }
  }

  Future<bool> testDraftConfiguration(EmailConfig config) async {
    if (!_beginTesting(config.id)) {
      return false;
    }

    try {
      final result = await _testEmailConfiguration(config);
      return result.fold(
        (success) {
          _error = null;
          return success;
        },
        (failure) {
          final f = failure as Failure;
          _error = _formatTestErrorMessage(f.message);
          return false;
        },
      );
    } on Object catch (e) {
      _error = _formatTestErrorMessage('Erro ao testar configuracao: $e');
      return false;
    } finally {
      _endTesting(config.id);
      _scheduleHistoryReload();
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

  Future<EmailConfig?> connectOAuth({
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) async {
    _error = null;
    notifyListeners();

    final result = await _oauthSmtpService.connect(
      configId: config.id,
      provider: provider,
    );

    return result.fold(
      (state) {
        final updated = config.copyWith(
          authMode: provider == SmtpOAuthProvider.google
              ? SmtpAuthMode.oauthGoogle
              : SmtpAuthMode.oauthMicrosoft,
          oauthProvider: provider,
          oauthAccountEmail: state.accountEmail,
          oauthTokenKey: state.tokenKey,
          oauthConnectedAt: state.connectedAt,
        );
        _error = null;
        return updated;
      },
      (failure) {
        final f = failure as Failure;
        _error = f.message;
        notifyListeners();
        return null;
      },
    );
  }

  Future<EmailConfig?> reconnectOAuth({
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) async {
    _error = null;
    notifyListeners();

    final result = await _oauthSmtpService.reconnect(
      configId: config.id,
      provider: provider,
    );

    return result.fold(
      (state) {
        final updated = config.copyWith(
          authMode: provider == SmtpOAuthProvider.google
              ? SmtpAuthMode.oauthGoogle
              : SmtpAuthMode.oauthMicrosoft,
          oauthProvider: provider,
          oauthAccountEmail: state.accountEmail,
          oauthTokenKey: state.tokenKey,
          oauthConnectedAt: state.connectedAt,
        );
        _error = null;
        return updated;
      },
      (failure) {
        final f = failure as Failure;
        _error = f.message;
        notifyListeners();
        return null;
      },
    );
  }

  Future<EmailConfig> disconnectOAuth(EmailConfig config) async {
    _error = null;
    notifyListeners();

    final tokenKey = config.oauthTokenKey?.trim() ?? '';
    if (tokenKey.isNotEmpty) {
      final result = await _oauthSmtpService.disconnect(tokenKey: tokenKey);
      if (result.isError()) {
        final failure = result.exceptionOrNull();
        if (failure is Failure) {
          _error = failure.message;
          notifyListeners();
        }
      }
    }

    return config.copyWith(
      authMode: SmtpAuthMode.password,
      clearOAuthProvider: true,
      clearOAuthAccountEmail: true,
      clearOAuthTokenKey: true,
      clearOAuthConnectedAt: true,
    );
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

  Future<String?> getPrimaryRecipientEmail(String configId) async {
    final config = _findConfigById(configId);
    if (config != null && config.recipients.isNotEmpty) {
      final recipient = config.recipients.first.trim();
      if (recipient.isNotEmpty) {
        return recipient;
      }
    }

    final result = await _emailNotificationTargetRepository.getByConfigId(
      configId,
    );
    return result.fold(
      (targets) {
        if (targets.isEmpty) {
          return null;
        }
        final recipient = targets.first.recipientEmail.trim();
        return recipient.isEmpty ? null : recipient;
      },
      (_) => null,
    );
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

  Future<void> refreshTestHistory() async {
    await _loadTestHistory();
  }

  void _scheduleHistoryReload() {
    _historyReloadTimer?.cancel();
    _historyReloadTimer = Timer(
      const Duration(milliseconds: 300),
      _loadTestHistory,
    );
  }

  Future<void> setHistoryPeriod(NotificationHistoryPeriod period) async {
    if (_historyPeriod == period) {
      return;
    }
    _historyPeriod = period;
    await _loadTestHistory();
  }

  Future<void> setHistoryConfigFilter(String? configId) async {
    if (_historyConfigIdFilter == configId) {
      return;
    }
    _historyConfigIdFilter = configId;
    await _loadTestHistory();
  }

  Future<String?> _resolvePrimaryRecipient(EmailConfig config) async {
    final recipient = config.recipients.isNotEmpty
        ? config.recipients.first.trim()
        : '';
    if (recipient.isNotEmpty) {
      return recipient;
    }

    final existingTargetsResult = await _emailNotificationTargetRepository
        .getByConfigId(config.id);

    return existingTargetsResult.fold(
      (targets) {
        if (targets.isEmpty) {
          return null;
        }
        final legacyRecipient = targets.first.recipientEmail.trim();
        return legacyRecipient.isEmpty ? null : legacyRecipient;
      },
      (failure) {
        final f = failure as Failure;
        _error = f.message;
        return null;
      },
    );
  }

  Future<void> _loadTestHistory({bool notify = true}) async {
    _isHistoryLoading = true;
    _historyError = null;
    if (notify) {
      notifyListeners();
    }

    final startAt = _resolveHistoryStart(_historyPeriod);
    final result = await _emailTestAuditRepository.getRecent(
      configId: _historyConfigIdFilter,
      startAt: startAt,
      endAt: DateTime.now(),
      limit: 200,
    );

    result.fold(
      (history) {
        _testHistory = history;
        _historyError = null;
      },
      (failure) {
        final f = failure as Failure;
        _testHistory = const [];
        _historyError = f.message;
      },
    );

    _isHistoryLoading = false;
    if (notify) {
      notifyListeners();
    }
  }

  DateTime? _resolveHistoryStart(NotificationHistoryPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case NotificationHistoryPeriod.last24Hours:
        return now.subtract(const Duration(hours: 24));
      case NotificationHistoryPeriod.last7Days:
        return now.subtract(const Duration(days: 7));
      case NotificationHistoryPeriod.last30Days:
        return now.subtract(const Duration(days: 30));
      case NotificationHistoryPeriod.all:
        return null;
    }
  }

  String _formatTestErrorMessage(String rawMessage) {
    final message = rawMessage.trim();
    if (message.isEmpty) {
      return 'Falha ao testar configuracao SMTP';
    }

    final lower = message.toLowerCase();
    if (lower.contains('autenticacao smtp')) {
      return 'Falha de autenticacao SMTP. Verifique usuario, senha e porta/SSL.\n$message';
    }
    if (lower.contains('nao foi possivel conectar') ||
        lower.contains('socket') ||
        lower.contains('timeout')) {
      return 'Falha de conectividade com o servidor SMTP.\n$message';
    }
    if (lower.contains('rejeitou a mensagem')) {
      return 'Servidor SMTP rejeitou a mensagem de teste.\n$message';
    }
    if (lower.contains('e-mail de destino') ||
        lower.contains('mensagem de e-mail invalida')) {
      return 'Falha de validacao da mensagem de teste.\n$message';
    }

    return message;
  }

  bool _beginTesting(String configId) {
    if (_testingConfigIds.contains(configId)) {
      _error =
          'Ja existe um teste de conexao em execucao para esta configuracao';
      notifyListeners();
      return false;
    }

    _testingConfigIds.add(configId);
    _isTesting = _testingConfigIds.isNotEmpty;
    _testingConfigId = configId;
    _error = null;
    notifyListeners();
    return true;
  }

  void _endTesting(String configId) {
    _testingConfigIds.remove(configId);
    _isTesting = _testingConfigIds.isNotEmpty;
    _testingConfigId = _testingConfigIds.isEmpty
        ? null
        : _testingConfigIds.first;
    notifyListeners();
  }
}
