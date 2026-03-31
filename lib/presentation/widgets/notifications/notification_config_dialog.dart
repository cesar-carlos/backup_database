import 'dart:ui' show PlatformDispatcher;

import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/compatibility/feature_disable_reason.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:zard/zard.dart';

class NotificationConfigDialog extends StatefulWidget {
  const NotificationConfigDialog({
    super.key,
    this.initialConfig,
    this.initialRecipientEmail,
    this.onTestConfiguration,
    this.onConnectOAuth,
    this.onReconnectOAuth,
    this.onDisconnectOAuth,
  });

  final EmailConfig? initialConfig;
  final String? initialRecipientEmail;
  final Future<String?> Function(EmailConfig config)? onTestConfiguration;
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
    Future<String?> Function(EmailConfig config)? onTestConfiguration,
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
        onTestConfiguration: onTestConfiguration,
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
  late Schema<String> _configNameSchema;
  late Schema<String> _smtpServerSchema;
  late Schema<String> _emailSchema;
  late Schema<String> _recipientEmailSchema;
  late Schema<String> _passwordSchema;
  String? _schemaLanguageCode;
  bool _attachLog = false;
  bool _isTestingConfiguration = false;
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
      text:
          config?.configName ??
          appLocaleStringForLocale(
            PlatformDispatcher.instance.locale,
            'Configuração SMTP',
            'SMTP configuration',
          ),
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
    _attachLog = config?.attachLog ?? false;

    final features = getIt<FeatureAvailabilityService>();
    if (!features.isExternalBrowserOAuthEnabled && _authMode.isOAuth) {
      _authMode = SmtpAuthMode.password;
      _oauthProvider = null;
      _oauthAccountEmail = null;
      _oauthTokenKey = null;
      _oauthConnectedAt = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (_schemaLanguageCode == code) {
      return;
    }
    _schemaLanguageCode = code;
    _configNameSchema = z.string().min(
      1,
      message: appLocaleString(
        context,
        'Nome da configuração é obrigatório',
        'Configuration name is required',
      ),
    );
    _smtpServerSchema = z.string().min(
      1,
      message: appLocaleString(
        context,
        'Servidor SMTP é obrigatório',
        'SMTP server is required',
      ),
    );
    _emailSchema = z
        .string()
        .min(
          1,
          message: appLocaleString(
            context,
            'E-mail é obrigatório',
            'E-mail is required',
          ),
        )
        .email(
          message: appLocaleString(
            context,
            'E-mail inválido',
            'Invalid e-mail',
          ),
        );
    _recipientEmailSchema = z.string().email(
      message: appLocaleString(
        context,
        'E-mail de destino inválido',
        'Invalid destination e-mail',
      ),
    );
    _passwordSchema = z.string().min(
      1,
      message: appLocaleString(
        context,
        'Senha é obrigatória',
        'Password is required',
      ),
    );
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
      return null;
    }

    final recipient = _recipientEmailController.text.trim();
    final current = widget.initialConfig;
    return EmailConfig(
      id: _draftConfigId,
      configName: _configNameController.text.trim(),
      senderName:
          current?.senderName ??
          appLocaleString(context, 'Sistema de Backup', 'Backup system'),
      fromEmail: _emailController.text.trim(),
      fromName:
          current?.fromName ??
          appLocaleString(context, 'Sistema de Backup', 'Backup system'),
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

    Navigator.of(context).pop(config);
  }

  Future<void> _testConfiguration() async {
    final onTestConfiguration = widget.onTestConfiguration;
    if (onTestConfiguration == null) {
      return;
    }

    final config = _buildConfig();
    if (config == null) {
      return;
    }

    setState(() {
      _isTestingConfiguration = true;
    });

    final errorMessage = await onTestConfiguration(config);
    if (!mounted) {
      return;
    }

    setState(() {
      _isTestingConfiguration = false;
    });

    if (errorMessage == null) {
      await MessageModal.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Configuração SMTP testada com sucesso.',
          'SMTP configuration tested successfully.',
        ),
      );
      return;
    }

    await MessageModal.showError(
      context,
      message: errorMessage,
    );
  }

  Future<void> _connectOAuth() async {
    if (!getIt<FeatureAvailabilityService>().isExternalBrowserOAuthEnabled) {
      return;
    }
    final onConnectOAuth = widget.onConnectOAuth;
    if (onConnectOAuth == null) {
      return;
    }

    final provider = _selectedOAuthProvider;
    if (provider == null) {
      await MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Selecione um provedor OAuth para conectar.',
          'Select an OAuth provider to connect.',
        ),
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
        message: appLocaleString(
          context,
          'Falha ao conectar conta OAuth SMTP.',
          'Failed to connect SMTP OAuth account.',
        ),
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
      message: appLocaleString(
        context,
        'Conta OAuth SMTP conectada com sucesso.',
        'SMTP OAuth account connected successfully.',
      ),
    );
  }

  Future<void> _reconnectOAuth() async {
    if (!getIt<FeatureAvailabilityService>().isExternalBrowserOAuthEnabled) {
      return;
    }
    final onReconnectOAuth = widget.onReconnectOAuth;
    if (onReconnectOAuth == null) {
      return;
    }

    final provider = _selectedOAuthProvider;
    if (provider == null) {
      await MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Selecione um provedor OAuth para reconectar.',
          'Select an OAuth provider to reconnect.',
        ),
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
        message: appLocaleString(
          context,
          'Falha ao reconectar conta OAuth SMTP.',
          'Failed to reconnect SMTP OAuth account.',
        ),
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
      message: appLocaleString(
        context,
        'Conta OAuth SMTP reconectada com sucesso.',
        'SMTP OAuth account reconnected successfully.',
      ),
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
      message: appLocaleString(
        context,
        'Conexão OAuth SMTP removida. Modo senha reativado.',
        'SMTP OAuth connection removed. Password mode restored.',
      ),
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
    return _validateWithSchema(_configNameSchema, value?.trim() ?? '');
  }

  String? _validateSmtpServer(String? value) {
    return _validateWithSchema(_smtpServerSchema, value?.trim() ?? '');
  }

  String? _validateEmail(String? value) {
    return _validateWithSchema(_emailSchema, value?.trim() ?? '');
  }

  String? _validateRecipientEmail(String? value) {
    final recipient = value?.trim() ?? '';
    if (recipient.isEmpty) {
      return null;
    }
    return _validateWithSchema(_recipientEmailSchema, recipient);
  }

  String? _validatePassword(String? value) {
    if (_authMode != SmtpAuthMode.password) {
      return null;
    }
    return _validateWithSchema(_passwordSchema, value?.trim() ?? '');
  }

  String? _validateWithSchema(Schema<String> schema, String value) {
    final result = schema.safeParse(value);
    if (result.success) {
      return null;
    }
    final issues = result.error?.issues;
    if (issues == null || issues.isEmpty) {
      return appLocaleString(context, 'Valor inválido', 'Invalid value');
    }
    return issues.first.message;
  }

  @override
  Widget build(BuildContext context) {
    final features = getIt<FeatureAvailabilityService>();
    final oauthModesAvailable = features.isExternalBrowserOAuthEnabled;
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
                  ? appLocaleString(
                      context,
                      'Editar configuração de e-mail',
                      'Edit e-mail configuration',
                    )
                  : appLocaleString(
                      context,
                      'Nova configuração de e-mail',
                      'New e-mail configuration',
                    ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
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
                  recipientEmailValidator: _validateRecipientEmail,
                  passwordValidator: _validatePassword,
                ),
                const SizedBox(height: 16),
                _SmtpAuthenticationSection(
                  authMode: _authMode,
                  isBusy: _isConnectingOAuth,
                  oauthAccountEmail: _oauthAccountEmail,
                  oauthConnectedAt: _oauthConnectedAt,
                  oauthModesAvailable: oauthModesAvailable,
                  oauthUnavailableReason:
                      features.externalBrowserOAuthDisabledReason,
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
                _AttachLogSection(
                  attachLog: _attachLog,
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
      ),
      actions: [
        Button(
          onPressed: _isTestingConfiguration || _isConnectingOAuth
              ? null
              : _testConfiguration,
          child: _isTestingConfiguration
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      appLocaleString(context, 'Testando...', 'Testing...'),
                    ),
                  ],
                )
              : Text(
                  appLocaleString(
                    context,
                    'Testar configuração',
                    'Test configuration',
                  ),
                ),
        ),
        const CancelButton(),
        SaveButton(
          onPressed: _isTestingConfiguration || _isConnectingOAuth
              ? null
              : _submit,
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
    required this.oauthModesAvailable,
    required this.oauthUnavailableReason,
    required this.onAuthModeChanged,
    required this.onConnect,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final SmtpAuthMode authMode;
  final bool isBusy;
  final String? oauthAccountEmail;
  final DateTime? oauthConnectedAt;
  final bool oauthModesAvailable;
  final FeatureDisableReason? oauthUnavailableReason;
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
        if (!oauthModesAvailable) ...[
          InfoBar(
            title: Text(
              appLocaleString(
                context,
                'OAuth SMTP',
                'SMTP OAuth',
              ),
            ),
            content: Text(
              localizeCompatibilityReason(
                context,
                reason: oauthUnavailableReason,
                fallbackPt: 'Não disponível nesta versão do Windows.',
                fallbackEn: 'Not available on this Windows version.',
              ),
            ),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          appLocaleString(context, 'Autenticação SMTP', 'SMTP authentication'),
          style: FluentTheme.of(context).typography.subtitle?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        InfoLabel(
          label: appLocaleString(
            context,
            'Modo de autenticação',
            'Authentication mode',
          ),
          child: ComboBox<SmtpAuthMode>(
            value: authMode,
            isExpanded: true,
            items: [
              ComboBoxItem(
                value: SmtpAuthMode.password,
                child: Text(
                  appLocaleString(context, 'Senha SMTP', 'SMTP password'),
                ),
              ),
              if (oauthModesAvailable) ...[
                const ComboBoxItem(
                  value: SmtpAuthMode.oauthGoogle,
                  child: Text('Google OAuth2'),
                ),
                const ComboBoxItem(
                  value: SmtpAuthMode.oauthMicrosoft,
                  child: Text('Microsoft OAuth2'),
                ),
              ],
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
                ? appLocaleString(
                    context,
                    'Conta conectada: $oauthAccountEmail',
                    'Account connected: $oauthAccountEmail',
                  )
                : appLocaleString(
                    context,
                    'Nenhuma conta OAuth conectada',
                    'No OAuth account connected',
                  ),
          ),
          if (connectedAt != null)
            Text(
              appLocaleString(
                context,
                'Conectado em: $connectedAt',
                'Connected at: $connectedAt',
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(
                onPressed: isBusy ? null : onConnect,
                child: Text(
                  isBusy
                      ? appLocaleString(
                          context,
                          'Conectando...',
                          'Connecting...',
                        )
                      : appLocaleString(context, 'Conectar', 'Connect'),
                ),
              ),
              Button(
                onPressed: isBusy ? null : onReconnect,
                child: Text(
                  appLocaleString(context, 'Reconectar', 'Reconnect'),
                ),
              ),
              Button(
                onPressed: isBusy ? null : onDisconnect,
                child: Text(
                  appLocaleString(context, 'Desconectar', 'Disconnect'),
                ),
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
    required this.recipientEmailValidator,
    required this.passwordValidator,
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
  final String? Function(String?) recipientEmailValidator;
  final String? Function(String?) passwordValidator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: configNameController,
          label: appLocaleString(
            context,
            'Nome da configuração',
            'Configuration name',
          ),
          hint: appLocaleString(context, 'SMTP principal', 'Primary SMTP'),
          validator: configNameValidator,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: smtpServerController,
          label: appLocaleString(context, 'Servidor SMTP', 'SMTP server'),
          hint: appLocaleString(
            context,
            'smtp.exemplo.com',
            'smtp.example.com',
          ),
          validator: smtpServerValidator,
        ),
        const SizedBox(height: 16),
        NumericField(
          controller: smtpPortController,
          label: appLocaleString(context, 'Porta', 'Port'),
          hint: '587',
          prefixIcon: FluentIcons.number_field,
          minValue: 1,
          maxValue: 65535,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: emailController,
          label: appLocaleString(
            context,
            'E-mail (usuário SMTP)',
            'E-mail (SMTP user)',
          ),
          keyboardType: TextInputType.emailAddress,
          hint: appLocaleString(
            context,
            'seu-email@exemplo.com',
            'your-email@example.com',
          ),
          validator: emailValidator,
        ),
        const SizedBox(height: 16),
        PasswordField(
          controller: passwordController,
          hint: appLocaleString(
            context,
            'Senha do e-mail',
            'E-mail password',
          ),
          validator: passwordValidator,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: recipientEmailController,
          label: appLocaleString(
            context,
            'E-mail de destino (opcional para teste)',
            'Destination e-mail (optional for test)',
          ),
          keyboardType: TextInputType.emailAddress,
          hint: appLocaleString(
            context,
            'destino@exemplo.com',
            'recipient@example.com',
          ),
          validator: recipientEmailValidator,
        ),
      ],
    );
  }
}

class _AttachLogSection extends StatelessWidget {
  const _AttachLogSection({
    required this.attachLog,
    required this.onAttachLogChanged,
  });

  final bool attachLog;
  final ValueChanged<bool> onAttachLogChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 16),
        Text(
          appLocaleString(context, 'Anexos', 'Attachments'),
          style: FluentTheme.of(context).typography.subtitle?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: appLocaleString(
            context,
            'Incluir detalhamento/logs no e-mail',
            'Include details/logs in e-mail',
          ),
          child: ToggleSwitch(
            checked: attachLog,
            onChanged: onAttachLogChanged,
          ),
        ),
      ],
    );
  }
}
