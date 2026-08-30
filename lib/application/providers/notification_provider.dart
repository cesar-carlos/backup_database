import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/application/providers/dispose_guard_mixin.dart';
import 'package:backup_database/application/providers/notification/notification_config_store.dart';
import 'package:backup_database/application/providers/notification/notification_history_loader.dart';
import 'package:backup_database/application/providers/notification/notification_oauth_coordinator.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:backup_database/domain/services/i_oauth_smtp_service.dart';
import 'package:backup_database/domain/use_cases/notifications/test_email_configuration.dart';
import 'package:flutter/foundation.dart';

export 'package:backup_database/application/providers/notification/notification_history_loader.dart'
    show NotificationHistoryPeriod;

class NotificationProvider extends ChangeNotifier
    with AsyncStateMixin, DisposeGuardMixin {
  NotificationProvider({
    required IEmailConfigRepository emailConfigRepository,
    required IEmailNotificationTargetRepository
    emailNotificationTargetRepository,
    required IEmailTestAuditRepository emailTestAuditRepository,
    required IOAuthSmtpService oauthSmtpService,
    required this._testEmailConfiguration,
  }) : _emailConfigRepository = emailConfigRepository {
    _store = NotificationConfigStore(
      emailConfigRepository: emailConfigRepository,
      targetRepository: emailNotificationTargetRepository,
      notifyListeners: notifyListeners,
      clearError: clearError,
      setErrorManual: setErrorManual,
    );
    _history = NotificationHistoryLoader(
      auditRepository: emailTestAuditRepository,
      notifyListeners: notifyListeners,
      isDisposed: () => isDisposed,
    );
    _oauth = NotificationOAuthCoordinator(
      oauthSmtpService: oauthSmtpService,
      notifyListeners: notifyListeners,
      clearError: clearError,
      setErrorManual: setErrorManual,
    );
  }

  final IEmailConfigRepository _emailConfigRepository;
  final TestEmailConfiguration _testEmailConfiguration;
  late final NotificationConfigStore _store;
  late final NotificationHistoryLoader _history;
  late final NotificationOAuthCoordinator _oauth;

  bool _isTesting = false;
  String? _testingConfigId;
  final Set<String> _testingConfigIds = <String>{};

  List<EmailConfig> get configs => _store.configs;
  String? get selectedConfigId => _store.selectedConfigId;
  List<EmailNotificationTarget> get targets => _store.targets;

  EmailConfig? get selectedConfig => _store.selectedConfig;

  EmailConfig? get emailConfig => selectedConfig;
  List<EmailTestAudit> get testHistory => _history.history;
  String? get historyError => _history.error;
  bool get isHistoryLoading => _history.isLoading;
  NotificationHistoryPeriod get historyPeriod => _history.period;
  String? get historyConfigIdFilter => _history.configIdFilter;
  bool get isTesting => _isTesting;
  String? get testingConfigId => _testingConfigId;
  bool get isConfigured => selectedConfig != null && selectedConfig!.enabled;
  bool isConfigUnderTest(String configId) =>
      _testingConfigIds.contains(configId);
  bool isConfigUpdating(String configId) =>
      _store.updatingConfigIds.contains(configId);
  Set<String> get updatingConfigIds =>
      Set<String>.unmodifiable(_store.updatingConfigIds);

  Future<void> loadConfig() async {
    await loadConfigs();
  }

  Future<void> loadConfigs() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao carregar configuração de e-mail',
      action: () async {
        final result = await _emailConfigRepository.getAll();
        await result.fold(
          (configs) async {
            _store.applyLoadedConfigs(configs);

            if (_store.configs.isEmpty) {
              _history.clear();
              return;
            }

            _history.configIdFilter ??= _store.selectedConfigId;
            final hasHistoryFilter = _store.configs.any(
              (c) => c.id == _history.configIdFilter,
            );
            if (!hasHistoryFilter) {
              _history.configIdFilter = _store.selectedConfigId;
            }

            final selected = selectedConfig;
            if (selected != null) {
              await _store.loadTargetsByConfigId(selected.id, notify: false);
            }
            await _history.load(notify: false);
          },
          (failure) {
            _store.applyLoadedConfigs(const []);
            _history.clear();
            throw failure;
          },
        );
      },
    );
  }

  Future<void> selectConfig(String? configId) async {
    if (configId == _store.selectedConfigId) {
      return;
    }

    _store.selectedConfigId = configId;
    _history.configIdFilter = configId;
    notifyListeners();

    if (configId == null) {
      _store.targets = const [];
      _history.history = const [];
      notifyListeners();
      return;
    }

    await _store.loadTargetsByConfigId(configId);
    await _history.load();
  }

  Future<bool> saveConfig(EmailConfig config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao salvar configuração',
      action: () async {
        final result = await _emailConfigRepository.save(config);
        return result.fold(
          (savedConfig) {
            _store.selectedConfigId = savedConfig.id;
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    if (ok ?? false) {
      await loadConfigs();
      return true;
    }
    return false;
  }

  Future<bool> deleteConfigById(String id) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao remover configuração',
      action: () async {
        final result = await _emailConfigRepository.deleteById(id);
        return result.fold(
          (_) {
            if (_store.selectedConfigId == id) {
              _store.selectedConfigId = null;
            }
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    if (ok ?? false) {
      await loadConfigs();
      return true;
    }
    return false;
  }

  Future<bool> deleteSelectedConfig() async {
    final selected = selectedConfig;
    if (selected == null) {
      setErrorManual('Nenhuma configuração selecionada');
      return false;
    }

    return deleteConfigById(selected.id);
  }

  Future<bool> testConfiguration([String? configId]) async {
    final config = configId == null
        ? selectedConfig
        : _store.findConfigById(configId);

    if (config == null) {
      setErrorManual('Nenhuma configuração de e-mail definida');
      return false;
    }

    return _runTest(config);
  }

  Future<bool> testDraftConfiguration(EmailConfig config) async {
    return _runTest(config);
  }

  Future<bool> _runTest(EmailConfig config) async {
    if (!_beginTesting(config.id)) {
      return false;
    }

    try {
      final result = await _testEmailConfiguration(config);
      return result.fold(
        (success) {
          clearError();
          return success;
        },
        (failure) {
          setErrorManual(
            _formatTestErrorMessage(
              AsyncStateMixin.extractFailureMessage(failure),
            ),
            code: AsyncStateMixin.extractFailureCode(failure),
          );
          return false;
        },
      );
    } on Object catch (e) {
      setErrorManual(
        _formatTestErrorMessage(
          'Erro ao testar configuração: '
          '${AsyncStateMixin.extractFailureMessage(e)}',
        ),
      );
      return false;
    } finally {
      _endTesting(config.id);
      _history.scheduleReload();
    }
  }

  Future<bool> toggleConfigEnabled(String configId, bool enabled) {
    return _store.toggleConfigEnabled(configId, enabled);
  }

  Future<EmailConfig?> connectOAuth({
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) {
    return _oauth.connect(config: config, provider: provider);
  }

  Future<EmailConfig?> reconnectOAuth({
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) {
    return _oauth.reconnect(config: config, provider: provider);
  }

  Future<EmailConfig> disconnectOAuth(EmailConfig config) {
    return _oauth.disconnect(config);
  }

  void toggleEnabled(bool enabled) {
    final config = selectedConfig;
    if (config != null) {
      unawaited(toggleConfigEnabled(config.id, enabled));
    }
  }

  Future<void> loadTargets(String configId) async {
    await _store.loadTargetsByConfigId(configId);
  }

  Future<String?> getPrimaryRecipientEmail(String configId) {
    return _store.primaryRecipientEmail(configId);
  }

  Future<bool> addTarget(EmailNotificationTarget target) {
    return _store.addTarget(target);
  }

  Future<bool> updateTarget(EmailNotificationTarget target) {
    return _store.updateTarget(target);
  }

  Future<bool> deleteTargetById(String targetId) {
    return _store.deleteTargetById(targetId);
  }

  Future<bool> toggleTargetEnabled(String targetId, bool enabled) {
    return _store.toggleTargetEnabled(targetId, enabled);
  }

  Future<void> refreshTestHistory() async {
    await _history.load();
  }

  Future<void> setHistoryPeriod(NotificationHistoryPeriod period) {
    return _history.setPeriod(period);
  }

  Future<void> setHistoryConfigFilter(String? configId) {
    return _history.setConfigFilter(configId);
  }

  String _formatTestErrorMessage(String rawMessage) {
    final message = rawMessage.trim();
    if (message.isEmpty) {
      return 'Falha ao testar configuração SMTP';
    }

    final lower = message.toLowerCase();
    if (lower.contains('autenticação smtp')) {
      return 'Falha de autenticação SMTP. Verifique usuário, senha e porta/SSL.\n$message';
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
      return 'Falha de validação da mensagem de teste.\n$message';
    }

    return message;
  }

  bool _beginTesting(String configId) {
    if (_testingConfigIds.contains(configId)) {
      setErrorManual(
        'Já existe um teste de conexão em execução para esta configuração',
      );
      return false;
    }

    _testingConfigIds.add(configId);
    _isTesting = _testingConfigIds.isNotEmpty;
    _testingConfigId = configId;
    clearError();
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

  @override
  void dispose() {
    _history.dispose();
    super.dispose();
  }
}
