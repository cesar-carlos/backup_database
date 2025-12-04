import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../application/providers/notification_provider.dart';
import '../../domain/entities/email_config.dart';
import '../widgets/common/common.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _smtpServerController;
  late final TextEditingController _smtpPortController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _recipientEmailController;
  
  bool _notifyOnSuccess = true;
  bool _notifyOnError = true;
  bool _attachLog = false;

  @override
  void initState() {
    super.initState();
    _smtpServerController = TextEditingController();
    _smtpPortController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _recipientEmailController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<NotificationProvider>();
      await provider.loadConfig();
      _loadConfig();
    });
  }

  @override
  void dispose() {
    _smtpServerController.dispose();
    _smtpPortController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _recipientEmailController.dispose();
    super.dispose();
  }

  void _loadConfig() {
    final provider = context.read<NotificationProvider>();
    
    if (provider.isLoading) {
      return;
    }
    
    final config = provider.emailConfig;

    if (config != null) {
      setState(() {
        _smtpServerController.text = config.smtpServer;
        _smtpPortController.text = config.smtpPort.toString();
        _emailController.text = config.username;
        _passwordController.text = config.password;
        _recipientEmailController.text = config.recipients.isNotEmpty
            ? config.recipients.first
            : '';
        _notifyOnSuccess = config.notifyOnSuccess;
        _notifyOnError = config.notifyOnError;
        _attachLog = config.attachLog;
      });
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final smtpPort = int.tryParse(_smtpPortController.text.trim());
    if (smtpPort == null) {
      MessageModal.showError(
        context,
        message: 'Porta SMTP inválida',
      );
      return;
    }

    final recipientEmail = _recipientEmailController.text.trim();
    if (recipientEmail.isEmpty) {
      MessageModal.showError(
        context,
        message: 'E-mail de destino é obrigatório',
      );
      return;
    }

    final provider = context.read<NotificationProvider>();
    final existingConfig = provider.emailConfig;

    final emailConfig = EmailConfig(
      id: existingConfig?.id,
      senderName: existingConfig?.senderName ?? 'Sistema de Backup',
      fromEmail: _emailController.text.trim(),
      fromName: existingConfig?.fromName ?? 'Sistema de Backup',
      smtpServer: _smtpServerController.text.trim(),
      smtpPort: smtpPort,
      username: _emailController.text.trim(),
      password: _passwordController.text,
      useSsl: smtpPort == 465,
      recipients: [recipientEmail],
      notifyOnSuccess: _notifyOnSuccess,
      notifyOnError: _notifyOnError,
      attachLog: _attachLog,
      enabled: existingConfig?.enabled ?? true,
      createdAt: existingConfig?.createdAt,
    );

    final success = await provider.saveConfig(emailConfig);

    if (!mounted) return;

    if (success) {
      MessageModal.showSuccess(
        context,
        message: 'Configuração salva com sucesso!',
      );
    } else {
      MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao salvar configuração',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('Configurações de Notificações por E-mail'),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer<NotificationProvider>(
              builder: (context, provider, child) {
                return AppCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextField(
                          controller: _smtpServerController,
                          label: 'Servidor SMTP',
                          hint: 'smtp.exemplo.com',
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Servidor SMTP é obrigatório';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        NumericField(
                          controller: _smtpPortController,
                          label: 'Porta',
                          hint: '587',
                          prefixIcon: FluentIcons.number_field,
                          minValue: 1,
                          maxValue: 65535,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _emailController,
                          label: 'E-mail',
                          keyboardType: TextInputType.emailAddress,
                          hint: 'seu-email@exemplo.com',
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'E-mail é obrigatório';
                            }
                            if (!value.contains('@')) {
                              return 'E-mail inválido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        PasswordField(
                          controller: _passwordController,
                          label: 'Senha',
                          hint: 'Senha do e-mail',
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _recipientEmailController,
                          label: 'E-mail de Destino',
                          keyboardType: TextInputType.emailAddress,
                          hint: 'destino@exemplo.com',
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'E-mail de destino é obrigatório';
                            }
                            if (!value.contains('@')) {
                              return 'E-mail inválido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        Text(
                          'Quando enviar notificações',
                          style: FluentTheme.of(context).typography.subtitle?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: 'Notificar em caso de sucesso',
                          child: ToggleSwitch(
                            checked: _notifyOnSuccess,
                            onChanged: (value) {
                              setState(() {
                                _notifyOnSuccess = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: 'Notificar em caso de erro',
                          child: ToggleSwitch(
                            checked: _notifyOnError,
                            onChanged: (value) {
                              setState(() {
                                _notifyOnError = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        Text(
                          'Detalhamento',
                          style: FluentTheme.of(context).typography.subtitle?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        InfoLabel(
                          label: 'Incluir detalhamento/logs no e-mail',
                          child: ToggleSwitch(
                            checked: _attachLog,
                            onChanged: (value) {
                              setState(() {
                                _attachLog = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Consumer<NotificationProvider>(
                              builder: (context, provider, child) {
                                return ActionButton(
                                  label: provider.isTesting
                                      ? 'Testando...'
                                      : 'Testar Conexão',
                                  icon: FluentIcons.network_tower,
                                  isLoading: provider.isTesting,
                                  onPressed: provider.isTesting
                                      ? null
                                      : () async {
                                          final success = await provider
                                              .testConfiguration();

                                          if (!mounted) return;

                                          if (success) {
                                            MessageModal.showSuccess(
                                              context,
                                              message: 'Teste de conexão realizado com sucesso!',
                                            );
                                          } else {
                                            MessageModal.showError(
                                              context,
                                              message: provider.error ?? 'Erro ao testar conexão',
                                            );
                                          }
                                        },
                                );
                              },
                            ),
                            const SizedBox(width: 16),
                            Consumer<NotificationProvider>(
                              builder: (context, provider, child) {
                                return SaveButton(
                                  onPressed: _saveConfig,
                                  isLoading: provider.isLoading,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
