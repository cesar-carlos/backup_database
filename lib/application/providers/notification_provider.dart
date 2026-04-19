import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
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

class NotificationProvider extends ChangeNotifier with AsyncStateMixin {
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
       _testEmailConfiguration = testEmailConfiguration;

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailNotificationTargetRepository _emailNotificationTargetRepository;
  final IEmailTestAuditRepository _emailTestAuditRepository;
  final IOAuthSmtpService _oauthSmtpService;
  final TestEmailConfiguration _testEmailConfiguration;

  List<EmailConfig> _configs = const [];
  String? _selectedConfigId;
  List<EmailNotificationTarget> _targets = const [];

  // Estado granular de testes por configuração: a UI mostra spinner por
  // linha, o que não cabe no contador único do mixin.
  bool _isTesting = false;
  String? _testingConfigId;
  final Set<String> _testingConfigIds = <String>{};

  // Estado granular do histórico: tem ciclo de vida independente do
  // CRUD principal de configs (recarregamento debounced + filtros).
  List<EmailTestAudit> _testHistory = const [];
  String? _historyError;
  bool _isHistoryLoading = false;
  NotificationHistoryPeriod _historyPeriod =
      NotificationHistoryPeriod.last7Days;
  String? _historyConfigIdFilter;
  Timer? _historyReloadTimer;
  int _historyLoadRequestId = 0;

  // Atualizações otimistas por configuração (toggle enabled).
  final Set<String> _updatingConfigIds = <String>{};

  bool _isDisposed = false;

  List<EmailConfig> get configs => _configs;
  String? get selectedConfigId => _selectedConfigId;
  List<EmailNotificationTarget> get targets => _targets;

  EmailConfig? get selectedConfig => _findConfigById(_selectedConfigId);

  // Compatibilidade com tela antiga (single-config).
  EmailConfig? get emailConfig => selectedConfig;
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
  bool isConfigUpdating(String configId) =>
      _updatingConfigIds.contains(configId);
  Set<String> get updatingConfigIds =>
      Set<String>.unmodifiable(_updatingConfigIds);

  /// Sobrescreve `notifyListeners` para curto-circuitar após dispose.
  /// Necessário porque `runAsync` (mixin) e os timers debounced de
  /// histórico podem disparar notificações depois que o provider já foi
  /// descartado pelo Provider tree.
  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

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
            _configs = configs;

            if (_configs.isEmpty) {
              _selectedConfigId = null;
              _targets = const [];
              _testHistory = const [];
              _historyConfigIdFilter = null;
              _historyError = null;
              return;
            }

            final hasSelected =
                _configs.any((c) => c.id == _selectedConfigId);
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

            final selected = selectedConfig;
            if (selected != null) {
              await _loadTargetsByConfigId(selected.id, notify: false);
            }
            await _loadTestHistory(notify: false);
          },
          (failure) {
            _configs = const [];
            _selectedConfigId = null;
            _targets = const [];
            _testHistory = const [];
            _historyConfigIdFilter = null;
            _historyError = null;
            throw failure;
          },
        );
      },
    );
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
        clearError();
      },
      (failure) {
        _targets = const [];
        setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
      },
    );

    if (notify) {
      notifyListeners();
    }
  }

  Future<bool> saveConfig(EmailConfig config) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao salvar configuração',
      action: () async {
        final result = await _emailConfigRepository.save(config);
        return result.fold(
          (savedConfig) {
            _selectedConfigId = savedConfig.id;
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    if (ok ?? false) {
      // Recarrega para puxar lista atualizada (inclui campos calculados
      // pelo backend de persistência).
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
            if (_selectedConfigId == id) {
              _selectedConfigId = null;
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
        : _findConfigById(configId);

    if (config == null) {
      setErrorManual('Nenhuma configuração de e-mail definida');
      return false;
    }

    return _runTest(config);
  }

  Future<bool> testDraftConfiguration(EmailConfig config) async {
    return _runTest(config);
  }

  /// Helper unificado para `testConfiguration` / `testDraftConfiguration`.
  /// Antes da centralização, esses dois métodos tinham try/catch/finally
  /// idênticos, com risco de divergir na manutenção.
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
        _formatTestErrorMessage('Erro ao testar configuração: $e'),
      );
      return false;
    } finally {
      _endTesting(config.id);
      _scheduleHistoryReload();
    }
  }

  Future<bool> toggleConfigEnabled(String configId, bool enabled) async {
    if (_updatingConfigIds.contains(configId)) {
      return false;
    }

    final config = _findConfigById(configId);
    if (config == null) {
      setErrorManual('Configuração não encontrada');
      return false;
    }

    final previousConfig = config;
    final optimisticConfig = config.copyWith(enabled: enabled);
    _replaceConfigInMemory(optimisticConfig);
    _updatingConfigIds.add(configId);
    clearError();
    notifyListeners();

    try {
      final result = await _emailConfigRepository.save(optimisticConfig);

      return result.fold(
        (_) {
          clearError();
          return true;
        },
        (failure) {
          _replaceConfigInMemory(previousConfig);
          setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
          return false;
        },
      );
    } on Object catch (e) {
      _replaceConfigInMemory(previousConfig);
      setErrorManual('Erro ao atualizar status da configuração: $e');
      return false;
    } finally {
      _updatingConfigIds.remove(configId);
      notifyListeners();
    }
  }

  Future<EmailConfig?> connectOAuth({
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) async {
    return _runOAuthOperation(
      () => _oauthSmtpService.connect(
        configId: config.id,
        provider: provider,
      ),
      config: config,
      provider: provider,
    );
  }

  Future<EmailConfig?> reconnectOAuth({
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) async {
    return _runOAuthOperation(
      () => _oauthSmtpService.reconnect(
        configId: config.id,
        provider: provider,
      ),
      config: config,
      provider: provider,
    );
  }

  /// Helper para `connectOAuth` / `reconnectOAuth`. Ambos retornam o mesmo
  /// shape e fazem o mesmo `copyWith` no sucesso — DRY puro.
  Future<EmailConfig?> _runOAuthOperation(
    Future<dynamic> Function() operation, {
    required EmailConfig config,
    required SmtpOAuthProvider provider,
  }) async {
    clearError();
    notifyListeners();

    final result = await operation();
    return (result as dynamic).fold(
      (state) {
        clearError();
        return config.copyWith(
          authMode: provider == SmtpOAuthProvider.google
              ? SmtpAuthMode.oauthGoogle
              : SmtpAuthMode.oauthMicrosoft,
          oauthProvider: provider,
          oauthAccountEmail: state.accountEmail as String?,
          oauthTokenKey: state.tokenKey as String?,
          oauthConnectedAt: state.connectedAt as DateTime?,
        );
      },
      (failure) {
        setErrorManual(
          AsyncStateMixin.extractFailureMessage(failure as Object),
        );
        return null;
      },
    ) as EmailConfig?;
  }

  Future<EmailConfig> disconnectOAuth(EmailConfig config) async {
    clearError();
    notifyListeners();

    final tokenKey = config.oauthTokenKey?.trim() ?? '';
    if (tokenKey.isNotEmpty) {
      final result = await _oauthSmtpService.disconnect(tokenKey: tokenKey);
      if (result.isError()) {
        final failure = result.exceptionOrNull();
        if (failure != null) {
          setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
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
        setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
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
        setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
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
        setErrorManual(AsyncStateMixin.extractFailureMessage(failure));
        return false;
      },
    );
  }

  Future<bool> toggleTargetEnabled(String targetId, bool enabled) async {
    final target = _findTargetById(targetId);
    if (target == null) {
      setErrorManual('Destinatário não encontrado');
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

  Future<void> refreshTestHistory() async {
    await _loadTestHistory();
  }

  void _scheduleHistoryReload() {
    if (_isDisposed) {
      return;
    }
    _historyReloadTimer?.cancel();
    _historyReloadTimer = Timer(
      const Duration(milliseconds: 300),
      () {
        if (_isDisposed) {
          return;
        }
        _loadTestHistory();
      },
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

  Future<void> _loadTestHistory({bool notify = true}) async {
    final requestId = ++_historyLoadRequestId;
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

    if (_isDisposed || requestId != _historyLoadRequestId) {
      return;
    }

    result.fold(
      (history) {
        _testHistory = history;
        _historyError = null;
      },
      (failure) {
        _testHistory = const [];
        _historyError = AsyncStateMixin.extractFailureMessage(failure);
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

  void _replaceConfigInMemory(EmailConfig nextConfig) {
    final index = _configs.indexWhere((config) => config.id == nextConfig.id);
    if (index < 0) {
      return;
    }
    _configs = [
      for (var i = 0; i < _configs.length; i++)
        if (i == index) nextConfig else _configs[i],
    ];
  }

  @override
  void dispose() {
    _isDisposed = true;
    _historyReloadTimer?.cancel();
    super.dispose();
  }
}
