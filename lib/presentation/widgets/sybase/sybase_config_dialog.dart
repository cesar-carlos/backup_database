import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/sybase_config.dart';
import '../../../infrastructure/external/process/sybase_backup_service.dart';
import '../common/common.dart';

class SybaseConfigDialog extends StatefulWidget {
  final SybaseConfig? config;

  const SybaseConfigDialog({super.key, this.config});

  static Future<SybaseConfig?> show(
    BuildContext context, {
    SybaseConfig? config,
  }) async {
    return showDialog<SybaseConfig>(
      context: context,
      builder: (context) => SybaseConfigDialog(config: config),
    );
  }

  @override
  State<SybaseConfigDialog> createState() => _SybaseConfigDialogState();
}

class _SybaseConfigDialogState extends State<SybaseConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverNameController = TextEditingController();
  final _databaseNameController = TextEditingController();
  final _portController = TextEditingController(text: '2638');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isEnabled = true;
  bool _isTestingConnection = false;

  late final SybaseBackupService _backupService;

  bool get isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    _backupService = getIt<SybaseBackupService>();

    if (widget.config != null) {
      _nameController.text = widget.config!.name;
      _serverNameController.text = widget.config!.serverName;
      _databaseNameController.text = widget.config!.databaseName;
      _portController.text = widget.config!.port.toString();
      _usernameController.text = widget.config!.username;
      _passwordController.text = widget.config!.password;
      _isEnabled = widget.config!.enabled;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverNameController.dispose();
    _databaseNameController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isTestingConnection = true;
    });

    try {
      final port = int.tryParse(_portController.text.trim()) ?? 2638;

      if (port < 1 || port > 65535) {
        throw Exception('Porta inválida. Deve estar entre 1 e 65535.');
      }

      final testConfig = SybaseConfig(
        name: _nameController.text.trim(),
        serverName: _serverNameController.text.trim(),
        databaseName: _databaseNameController.text.trim(),
        databaseFile: '',
        port: port,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      final result = await _backupService.testConnection(testConfig);

      if (!mounted) return;

      result.fold(
        (_) {
          MessageModal.showSuccess(
            context,
            message: 'Conexão testada com sucesso!',
          );
        },
        (failure) {
          final f = failure as Failure;
          final errorMessage = f.message.isNotEmpty
              ? f.message
              : 'Erro desconhecido ao testar conexão';

          MessageModal.showError(
            context,
            title: 'Erro ao Testar Conexão',
            message: errorMessage,
          );
        },
      );
    } catch (e, stackTrace) {
      if (!mounted) return;

      LoggerService.error('Erro ao testar conexão Sybase', e, stackTrace);

      final errorMessage = e.toString().replaceAll('Exception: ', '');

      MessageModal.showError(
        context,
        title: 'Erro ao Testar Conexão',
        message: errorMessage.isNotEmpty ? errorMessage : 'Erro desconhecido',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final port = int.tryParse(_portController.text) ?? 2638;
    final config = SybaseConfig(
      id: widget.config?.id,
      name: _nameController.text.trim(),
      serverName: _serverNameController.text.trim(),
      databaseName: _databaseNameController.text.trim(),
      databaseFile: '',
      port: port,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      enabled: _isEnabled,
      createdAt: widget.config?.createdAt,
      updatedAt: widget.config?.updatedAt,
    );

    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(
        minWidth: 600,
        maxWidth: 600,
        maxHeight: 800,
      ),
      title: Row(
        children: [
          Icon(FluentIcons.server, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing
                  ? 'Editar Configuração Sybase'
                  : 'Nova Configuração Sybase',
              style: FluentTheme.of(context).typography.title,
            ),
          ),
        ],
      ),
      content: Container(
        constraints: const BoxConstraints(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _nameController,
                  label: 'Nome da Configuração',
                  hint: 'Ex: Produção Sybase',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nome é obrigatório';
                    }
                    return null;
                  },
                  prefixIcon: const Icon(FluentIcons.tag),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppTextField(
                        controller: _serverNameController,
                        label: 'Nome do Servidor (Engine Name)',
                        hint: 'Ex: VL (nome do serviço Sybase)',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Engine Name é obrigatório';
                          }
                          return null;
                        },
                        prefixIcon: const Icon(FluentIcons.server),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: NumericField(
                        controller: _portController,
                        label: 'Porta',
                        hint: '2638',
                        prefixIcon: FluentIcons.number_field,
                        minValue: 1,
                        maxValue: 65535,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _databaseNameController,
                  label: 'Nome do Banco de Dados (DBN)',
                  hint: 'Ex: VL (geralmente igual ao Engine Name)',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nome do banco de dados é obrigatório';
                    }
                    return null;
                  },
                  prefixIcon: const Icon(FluentIcons.database),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.info,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'O Engine Name e DBN geralmente são iguais ao nome do serviço Sybase (ex: VL)',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _usernameController,
                  label: 'Usuário',
                  hint: 'DBA ou usuário do Sybase',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Usuário é obrigatório';
                    }
                    return null;
                  },
                  prefixIcon: const Icon(FluentIcons.contact),
                ),
                const SizedBox(height: 16),
                PasswordField(controller: _passwordController),
                const SizedBox(height: 16),
                InfoLabel(
                  label: 'Habilitado',
                  child: ToggleSwitch(
                    checked: _isEnabled,
                    onChanged: (value) {
                      setState(() {
                        _isEnabled = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Permitir uso desta configuração em agendamentos',
                  style: FluentTheme.of(context).typography.caption,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        const CancelButton(),
        ActionButton(
          label: 'Testar Conexão',
          icon: FluentIcons.check_mark,
          onPressed: _testConnection,
          isLoading: _isTestingConnection,
        ),
        SaveButton(onPressed: _save, isEditing: isEditing),
      ],
    );
  }
}
