import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class NotificationConfigDialog extends StatefulWidget {
  const NotificationConfigDialog({
    super.key,
    this.initialConfig,
  });

  final EmailConfig? initialConfig;

  static Future<EmailConfig?> show(
    BuildContext context, {
    EmailConfig? initialConfig,
  }) {
    return showDialog<EmailConfig>(
      context: context,
      builder: (context) =>
          NotificationConfigDialog(initialConfig: initialConfig),
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
  late final TextEditingController _passwordController;
  bool _attachLog = false;

  bool get _isEditing => widget.initialConfig != null;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
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
    _passwordController = TextEditingController(text: config?.password ?? '');
    _attachLog = config?.attachLog ?? false;
  }

  @override
  void dispose() {
    _configNameController.dispose();
    _smtpServerController.dispose();
    _smtpPortController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final smtpPort = int.tryParse(_smtpPortController.text.trim());
    if (smtpPort == null) {
      MessageModal.showError(context, message: 'Porta SMTP invalida');
      return;
    }

    final current = widget.initialConfig;
    final config = EmailConfig(
      id: current?.id,
      configName: _configNameController.text.trim(),
      senderName: current?.senderName ?? 'Sistema de Backup',
      fromEmail: _emailController.text.trim(),
      fromName: current?.fromName ?? 'Sistema de Backup',
      smtpServer: _smtpServerController.text.trim(),
      smtpPort: smtpPort,
      username: _emailController.text.trim(),
      password: _passwordController.text,
      useSsl: smtpPort == 465,
      recipients: const [],
      attachLog: _attachLog,
      enabled: current?.enabled ?? true,
      createdAt: current?.createdAt,
    );

    Navigator.of(context).pop(config);
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
          Text(
            _isEditing
                ? 'Editar configuracao de e-mail'
                : 'Nova configuracao de e-mail',
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
                passwordController: _passwordController,
                configNameValidator: _validateConfigName,
                smtpServerValidator: _validateSmtpServer,
                emailValidator: _validateEmail,
              ),
              const SizedBox(height: 24),
              _NotificationBehaviorSection(
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
      actions: [
        const CancelButton(),
        SaveButton(
          onPressed: _submit,
          isEditing: _isEditing,
        ),
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
    required this.passwordController,
    required this.configNameValidator,
    required this.smtpServerValidator,
    required this.emailValidator,
  });

  final TextEditingController configNameController;
  final TextEditingController smtpServerController;
  final TextEditingController smtpPortController;
  final TextEditingController emailController;
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
          'Comportamento de notificacao',
          style: FluentTheme.of(context).typography.subtitle?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Os destinatarios e tipos de notificacao sao configurados na grade '
          'de destinatarios desta configuracao SMTP.',
        ),
        const SizedBox(height: 16),
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
