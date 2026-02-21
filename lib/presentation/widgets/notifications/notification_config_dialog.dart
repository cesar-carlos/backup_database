import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:uuid/uuid.dart';

class NotificationConfigDialog extends StatefulWidget {
  const NotificationConfigDialog({
    super.key,
    this.initialConfig,
    this.initialRecipientEmail,
    this.onTestConnection,
    this.getTestErrorMessage,
    this.onConnectOAuth,
    this.onReconnectOAuth,
    this.onDisconnectOAuth,
  });

  final EmailConfig? initialConfig;
  final String? initialRecipientEmail;
  final Future<bool> Function(EmailConfig config)? onTestConnection;
  final String? Function()? getTestErrorMessage;
  final Future<EmailConfig?> Function(
    EmailConfig config,
    SmtpOAuthProvider provider,
  )?
  onConnectOAuth;
  final Future<EmailConfig?> Function(
    EmailConfig config,
    SmtpOAuthProvider provider,
  )?
  onReconnectOAuth;
  final Future<EmailConfig> Function(EmailConfig config)? onDisconnectOAuth;

  static Future<EmailConfig?> show(
    BuildContext context, {
    EmailConfig? initialConfig,
    String? initialRecipientEmail,
    Future<bool> Function(EmailConfig config)? onTestConnection,
    String? Function()? getTestErrorMessage,
    Future<EmailConfig?> Function(
      EmailConfig config,
      SmtpOAuthProvider provider,
    )?
    onConnectOAuth,
    Future<EmailConfig?> Function(
      EmailConfig config,
      SmtpOAuthProvider provider,
    )?
    onReconnectOAuth,
    Future<EmailConfig> Function(EmailConfig config)? onDisconnectOAuth,
  }) {
    return showDialog<EmailConfig>(
      context: context,
      builder: (context) => NotificationConfigDialog(
        initialConfig: initialConfig,
        initialRecipientEmail: initialRecipientEmail,
        onTestConnection: onTestConnection,
        getTestErrorMessage: getTestErrorMessage,
        onConnectOAuth: onConnectOAuth,
        onReconnectOAuth: onReconnectOAuth,
        onDisconnectOAuth: onDisconnectOAuth,
      ),
    );
  }

  @override
  State<NotificationConfigDialog> createState() =>
      _NotificationConfigDialogState();
}

class _NotificationConfigDialogState extends State<NotificationConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _configNameController;
  late final TextEditingController _smtpServerController;
  late final TextEditingController _smtpPortController;
  late final TextEditingController _emailController;
  late final TextEditingController _recipientEmailController;
  late final TextEditingController _passwordController;
  late final String _draftConfigId;
  bool _notifyOnSuccess = true;
  bool _notifyOnError = true;
  bool _notifyOnWarning = true;
  bool _attachLog = false;
  bool _isTesting = false;
  bool _isConnectingOAuth = false;
  SmtpAuthMode _authMode = SmtpAuthMode.password;
  SmtpOAuthProvider? _oauthProvider;
  String? _oauthAccountEmail;
  String? _oauthTokenKey;
  DateTime? _oauthConnectedAt;

  bool get _isEditing => widget.initialConfig != null;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _draftConfigId = config?.id ?? const Uuid().v4();
    _configNameController = TextEditingController(
      text: config?.configName ?? 'Configuracao SMTP',
    );
    _smtpServerController = TextEditingController(
      text: config?.smtpServer ?? 'smtp.gmail.com',
    );
    _smtpPortController = TextEditingController(
      text: (config?.smtpPort ?? 587).toString(),
    );
    _emailController = TextEditingController(text: config?.username ?? '');
    final legacyRecipient = (config?.recipients.isNotEmpty ?? false)
        ? config!.recipients.first
        : '';
    _recipientEmailController = TextEditingController(
      text: widget.initialRecipientEmail ?? legacyRecipient,
    );
    _passwordController = TextEditingController(text: config?.password ?? '');
    _authMode = config?.authMode ?? SmtpAuthMode.password;
    _oauthProvider = config?.oauthProvider;
    _oauthAccountEmail = config?.oauthAccountEmail;
    _oauthTokenKey = config?.oauthTokenKey;
    _oauthConnectedAt = config?.oauthConnectedAt;
    _notifyOnSuccess = config?.notifyOnSuccess ?? true;
    _notifyOnError = config?.notifyOnError ?? true;
    _notifyOnWarning = config?.notifyOnWarning ?? true;
    _attachLog = config?.attachLog ?? false;
  }

  @override
  void dispose() {
    _configNameController.dispose();
    _smtpServerController.dispose();
    _smtpPortController.dispose();
    _emailController.dispose();
    _recipientEmailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  EmailConfig? _buildConfig() {
    if (!_formKey.currentState!.validate()) {
      return null;
    }

    final smtpPort = int.tryParse(_smtpPortController.text.trim());
    if (smtpPort == null) {
      MessageModal.showError(context, message: 'Porta SMTP invalida');
      return null;
    }

    final recipient = _recipientEmailController.text.trim();
    final current = widget.initialConfig;
    return EmailConfig(
      id: _draftConfigId,
      configName: _configNameController.text.trim(),
      senderName: current?.senderName ?? 'Sistema de Backup',
      fromEmail: _emailController.text.trim(),
      fromName: current?.fromName ?? 'Sistema de Backup',
      smtpServer: _smtpServerController.text.trim(),
      smtpPort: smtpPort,
      username: _emailController.text.trim(),
      password: _passwordController.text,
      useSsl: smtpPort == 465,
      authMode: _authMode,
      oauthProvider: _oauthProvider,
      oauthAccountEmail: _oauthAccountEmail,
      oauthTokenKey: _oauthTokenKey,
      oauthConnectedAt: _oauthConnectedAt,
      recipients: recipient.isEmpty ? const [] : [recipient],
      notifyOnSuccess: _notifyOnSuccess,
      notifyOnError: _notifyOnError,
      notifyOnWarning: _notifyOnWarning,
      attachLog: _attachLog,
      enabled: current?.enabled ?? true,
      createdAt: current?.createdAt,
    );
  }

  void _submit() {
    final config = _buildConfig();
    if (config == null) {
      return;
    }

    if (config.recipients.isEmpty) {
      MessageModal.showError(
        context,
        message: 'E-mail de destino e obrigatorio',
      );
      return;
    }

    Navigator.of(context).pop(config);
  }

  Future<void> _testConnection() async {
    final onTestConnection = widget.onTestConnection;
    if (onTestConnection == null) {
      return;
    }

    final config = _buildConfig();
    if (config == null) {
      return;
    }

    setState(() {
      _isTesting = true;
    });

    final success = await onTestConnection(config);
    if (!mounted) {
      return;
    }

    setState(() {
      _isTesting = false;
    });

    if (success) {
      await MessageModal.showSuccess(
        context,
        message:
            'Mensagem de teste aceita pelo servidor SMTP e encaminhada ao destinatario.\n\n'
            'Se nao encontrar na caixa de entrada, verifique spam/lixo eletronico, quarentena e filtros do provedor.',
      );
      return;
    }

    await MessageModal.showError(
      context,
      message:
          widget.getTestErrorMessage?.call() ??
          'Erro ao testar conexao SMTP. Verifique os dados informados.',
    );
  }

  Future<void> _connectOAuth() async {
    final onConnectOAuth = widget.onConnectOAuth;
    if (onConnectOAuth == null) {
      return;
    }

    final provider = _selectedOAuthProvider;
    if (provider == null) {
      await MessageModal.showError(
        context,
        message: 'Selecione um provedor OAuth para conectar.',
      );
      return;
    }

    final config = _buildConfig();
    if (config == null) {
      return;
    }

    setState(() {
      _isConnectingOAuth = true;
    });

    final updated = await onConnectOAuth(config, provider);
    if (!mounted) {
      return;
    }

    setState(() {
      _isConnectingOAuth = false;
    });

    if (updated == null) {
      await MessageModal.showError(
        context,
        message:
            widget.getTestErrorMessage?.call() ??
            'Falha ao conectar conta OAuth SMTP.',
      );
      return;
    }

    setState(() {
      _authMode = updated.authMode;
      _oauthProvider = updated.oauthProvider;
      _oauthAccountEmail = updated.oauthAccountEmail;
      _oauthTokenKey = updated.oauthTokenKey;
      _oauthConnectedAt = updated.oauthConnectedAt;
      if (updated.oauthAccountEmail != null &&
          updated.oauthAccountEmail!.trim().isNotEmpty) {
        _emailController.text = updated.oauthAccountEmail!.trim();
      }
    });

    await MessageModal.showSuccess(
      context,
      message: 'Conta OAuth SMTP conectada com sucesso.',
    );
  }

  Future<void> _reconnectOAuth() async {
    final onReconnectOAuth = widget.onReconnectOAuth;
    if (onReconnectOAuth == null) {
      return;
    }

    final provider = _selectedOAuthProvider;
    if (provider == null) {
      await MessageModal.showError(
        context,
        message: 'Selecione um provedor OAuth para reconectar.',
      );
      return;
    }

    final config = _buildConfig();
    if (config == null) {
      return;
    }

    setState(() {
      _isConnectingOAuth = true;
    });

    final updated = await onReconnectOAuth(config, provider);
    if (!mounted) {
      return;
    }

    setState(() {
      _isConnectingOAuth = false;
    });

    if (updated == null) {
      await MessageModal.showError(
        context,
        message:
            widget.getTestErrorMessage?.call() ??
            'Falha ao reconectar conta OAuth SMTP.',
      );
      return;
    }

    setState(() {
      _authMode = updated.authMode;
      _oauthProvider = updated.oauthProvider;
      _oauthAccountEmail = updated.oauthAccountEmail;
      _oauthTokenKey = updated.oauthTokenKey;
      _oauthConnectedAt = updated.oauthConnectedAt;
      if (updated.oauthAccountEmail != null &&
          updated.oauthAccountEmail!.trim().isNotEmpty) {
        _emailController.text = updated.oauthAccountEmail!.trim();
      }
    });

    await MessageModal.showSuccess(
      context,
      message: 'Conta OAuth SMTP reconectada com sucesso.',
    );
  }

  Future<void> _disconnectOAuth() async {
    final onDisconnectOAuth = widget.onDisconnectOAuth;
    if (onDisconnectOAuth == null) {
      setState(() {
        _authMode = SmtpAuthMode.password;
        _oauthProvider = null;
        _oauthAccountEmail = null;
        _oauthTokenKey = null;
        _oauthConnectedAt = null;
      });
      return;
    }

    final config = _buildConfig();
    if (config == null) {
      return;
    }

    setState(() {
      _isConnectingOAuth = true;
    });

    final updated = await onDisconnectOAuth(config);
    if (!mounted) {
      return;
    }

    setState(() {
      _isConnectingOAuth = false;
      _authMode = updated.authMode;
      _oauthProvider = updated.oauthProvider;
      _oauthAccountEmail = updated.oauthAccountEmail;
      _oauthTokenKey = updated.oauthTokenKey;
      _oauthConnectedAt = updated.oauthConnectedAt;
    });

    await MessageModal.showSuccess(
      context,
      message: 'Conexao OAuth SMTP removida. Modo senha reativado.',
    );
  }

  SmtpOAuthProvider? get _selectedOAuthProvider {
    if (_authMode == SmtpAuthMode.oauthGoogle) {
      return SmtpOAuthProvider.google;
    }
    if (_authMode == SmtpAuthMode.oauthMicrosoft) {
      return SmtpOAuthProvider.microsoft;
    }
    return _oauthProvider;
  }

  String? _validateConfigName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Nome da configuracao e obrigatorio';
    }
    return null;
  }

  String? _validateSmtpServer(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Servidor SMTP e obrigatorio';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'E-mail e obrigatorio';
    }
    if (!value.contains('@')) {
      return 'E-mail invalido';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(
        minWidth: 720,
        maxWidth: 720,
        maxHeight: 860,
      ),
      title: Row(
        children: [
          const Icon(FluentIcons.mail),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing
                  ? 'Editar configuracao de e-mail'
                  : 'Nova configuracao de e-mail',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SmtpSettingsSection(
                configNameController: _configNameController,
                smtpServerController: _smtpServerController,
                smtpPortController: _smtpPortController,
                emailController: _emailController,
                recipientEmailController: _recipientEmailController,
                passwordController: _passwordController,
                configNameValidator: _validateConfigName,
                smtpServerValidator: _validateSmtpServer,
                emailValidator: _validateEmail,
              ),
              const SizedBox(height: 16),
              _SmtpAuthenticationSection(
                authMode: _authMode,
                isBusy: _isConnectingOAuth,
                oauthAccountEmail: _oauthAccountEmail,
                oauthConnectedAt: _oauthConnectedAt,
                onAuthModeChanged: (mode) {
                  setState(() {
                    _authMode = mode;
                    if (mode == SmtpAuthMode.password) {
                      _oauthProvider = null;
                      _oauthAccountEmail = null;
                      _oauthTokenKey = null;
                      _oauthConnectedAt = null;
                    } else {
                      _oauthProvider = mode == SmtpAuthMode.oauthGoogle
                          ? SmtpOAuthProvider.google
                          : SmtpOAuthProvider.microsoft;
                    }
                  });
                },
                onConnect: _connectOAuth,
                onReconnect: _reconnectOAuth,
                onDisconnect: _disconnectOAuth,
              ),
              const SizedBox(height: 24),
              _NotificationBehaviorSection(
                notifyOnSuccess: _notifyOnSuccess,
                notifyOnError: _notifyOnError,
                notifyOnWarning: _notifyOnWarning,
                attachLog: _attachLog,
                onNotifyOnSuccessChanged: (value) {
                  setState(() {
                    _notifyOnSuccess = value;
                  });
                },
                onNotifyOnErrorChanged: (value) {
                  setState(() {
                    _notifyOnError = value;
                  });
                },
                onNotifyOnWarningChanged: (value) {
                  setState(() {
                    _notifyOnWarning = value;
                  });
                },
                onAttachLogChanged: (value) {
                  setState(() {
                    _attachLog = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton(
          label: 'Testar conexao',
          icon: FluentIcons.network_tower,
          isLoading: _isTesting,
          onPressed: _isTesting ? null : _testConnection,
        ),
        const CancelButton(),
        SaveButton(
          onPressed: _submit,
          isEditing: _isEditing,
        ),
      ],
    );
  }
}

class _SmtpAuthenticationSection extends StatelessWidget {
  const _SmtpAuthenticationSection({
    required this.authMode,
    required this.isBusy,
    required this.oauthAccountEmail,
    required this.oauthConnectedAt,
    required this.onAuthModeChanged,
    required this.onConnect,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final SmtpAuthMode authMode;
  final bool isBusy;
  final String? oauthAccountEmail;
  final DateTime? oauthConnectedAt;
  final ValueChanged<SmtpAuthMode> onAuthModeChanged;
  final Future<void> Function() onConnect;
  final Future<void> Function() onReconnect;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final isOAuth = authMode.isOAuth;
    final isConnected = oauthAccountEmail?.trim().isNotEmpty ?? false;
    final connectedAt = oauthConnectedAt?.toLocal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 10),
        Text(
          'Autenticacao SMTP',
          style: FluentTheme.of(context).typography.subtitle?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        InfoLabel(
          label: 'Modo de autenticacao',
          child: ComboBox<SmtpAuthMode>(
            value: authMode,
            isExpanded: true,
            items: const [
              ComboBoxItem(
                value: SmtpAuthMode.password,
                child: Text('Senha SMTP'),
              ),
              ComboBoxItem(
                value: SmtpAuthMode.oauthGoogle,
                child: Text('Google OAuth2'),
              ),
              ComboBoxItem(
                value: SmtpAuthMode.oauthMicrosoft,
                child: Text('Microsoft OAuth2'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                onAuthModeChanged(value);
              }
            },
          ),
        ),
        if (isOAuth) ...[
          const SizedBox(height: 12),
          Text(
            isConnected
                ? 'Conta conectada: $oauthAccountEmail'
                : 'Nenhuma conta OAuth conectada',
          ),
          if (connectedAt != null) Text('Conectado em: $connectedAt'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(
                onPressed: isBusy ? null : onConnect,
                child: Text(isBusy ? 'Conectando...' : 'Conectar'),
              ),
              Button(
                onPressed: isBusy ? null : onReconnect,
                child: const Text('Reconectar'),
              ),
              Button(
                onPressed: isBusy ? null : onDisconnect,
                child: const Text('Desconectar'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SmtpSettingsSection extends StatelessWidget {
  const _SmtpSettingsSection({
    required this.configNameController,
    required this.smtpServerController,
    required this.smtpPortController,
    required this.emailController,
    required this.recipientEmailController,
    required this.passwordController,
    required this.configNameValidator,
    required this.smtpServerValidator,
    required this.emailValidator,
  });

  final TextEditingController configNameController;
  final TextEditingController smtpServerController;
  final TextEditingController smtpPortController;
  final TextEditingController emailController;
  final TextEditingController recipientEmailController;
  final TextEditingController passwordController;
  final String? Function(String?) configNameValidator;
  final String? Function(String?) smtpServerValidator;
  final String? Function(String?) emailValidator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: configNameController,
          label: 'Nome da configuracao',
          hint: 'SMTP Principal',
          validator: configNameValidator,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: smtpServerController,
          label: 'Servidor SMTP',
          hint: 'smtp.exemplo.com',
          validator: smtpServerValidator,
        ),
        const SizedBox(height: 16),
        NumericField(
          controller: smtpPortController,
          label: 'Porta',
          hint: '587',
          prefixIcon: FluentIcons.number_field,
          minValue: 1,
          maxValue: 65535,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: emailController,
          label: 'E-mail (usuario SMTP)',
          keyboardType: TextInputType.emailAddress,
          hint: 'seu-email@exemplo.com',
          validator: emailValidator,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: recipientEmailController,
          label: 'E-mail de destino',
          keyboardType: TextInputType.emailAddress,
          hint: 'destino@exemplo.com',
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) {
              return null;
            }
            if (!email.contains('@')) {
              return 'E-mail de destino invalido';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        PasswordField(
          controller: passwordController,
          hint: 'Senha do e-mail',
        ),
      ],
    );
  }
}

class _NotificationBehaviorSection extends StatelessWidget {
  const _NotificationBehaviorSection({
    required this.notifyOnSuccess,
    required this.notifyOnError,
    required this.notifyOnWarning,
    required this.attachLog,
    required this.onNotifyOnSuccessChanged,
    required this.onNotifyOnErrorChanged,
    required this.onNotifyOnWarningChanged,
    required this.onAttachLogChanged,
  });

  final bool notifyOnSuccess;
  final bool notifyOnError;
  final bool notifyOnWarning;
  final bool attachLog;
  final ValueChanged<bool> onNotifyOnSuccessChanged;
  final ValueChanged<bool> onNotifyOnErrorChanged;
  final ValueChanged<bool> onNotifyOnWarningChanged;
  final ValueChanged<bool> onAttachLogChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Comportamento de notificacao',
          style: FluentTheme.of(context).typography.subtitle?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Os tipos de aviso sao configurados nesta configuracao SMTP.',
        ),
        const SizedBox(height: 16),
        _NotificationToggleField(
          label: 'Notificar em caso de sucesso',
          value: notifyOnSuccess,
          onChanged: onNotifyOnSuccessChanged,
        ),
        const SizedBox(height: 10),
        _NotificationToggleField(
          label: 'Notificar em caso de erro',
          value: notifyOnError,
          onChanged: onNotifyOnErrorChanged,
        ),
        const SizedBox(height: 10),
        _NotificationToggleField(
          label: 'Notificar em caso de aviso',
          value: notifyOnWarning,
          onChanged: onNotifyOnWarningChanged,
        ),
        const SizedBox(height: 10),
        _NotificationToggleField(
          label: 'Incluir detalhamento/logs no e-mail',
          value: attachLog,
          onChanged: onAttachLogChanged,
        ),
      ],
    );
  }
}

class _NotificationToggleField extends StatelessWidget {
  const _NotificationToggleField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InfoLabel(
      label: label,
      child: ToggleSwitch(
        checked: value,
        onChanged: onChanged,
      ),
    );
  }
}
