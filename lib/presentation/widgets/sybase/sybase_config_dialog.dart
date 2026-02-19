import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SybaseConfigDialog extends StatefulWidget {
  const SybaseConfigDialog({
    required this.backupService,
    super.key,
    this.config,
  });
  final SybaseConfig? config;
  final ISybaseBackupService backupService;

  static Future<SybaseConfig?> show(
    BuildContext context, {
    required ISybaseBackupService backupService,
    SybaseConfig? config,
  }) async {
    return showDialog<SybaseConfig>(
      context: context,
      builder: (context) =>
          SybaseConfigDialog(config: config, backupService: backupService),
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
  final _portController = TextEditingController(
    text: AppConstants.defaultSybasePort.toString(),
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isEnabled = true;
  bool _isTestingConnection = false;

  late final ISybaseBackupService _backupService;

  bool get isEditing => widget.config != null;

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  void initState() {
    super.initState();
    _backupService = widget.backupService;

    if (widget.config != null) {
      _nameController.text = widget.config!.name;
      _serverNameController.text = widget.config!.serverName;
      _databaseNameController.text = widget.config!.databaseNameValue;
      _portController.text = widget.config!.portValue.toString();
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
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isTestingConnection = true;
    });

    try {
      final port = int.tryParse(_portController.text.trim()) ?? 2638;

      if (port < 1 || port > 65535) {
        throw Exception(
          _t(
            'Porta invalida. Deve estar entre 1 e 65535.',
            'Invalid port. Must be between 1 and 65535.',
          ),
        );
      }

      final testConfig = SybaseConfig(
        name: _nameController.text.trim(),
        serverName: _serverNameController.text.trim(),
        databaseName: DatabaseName(_databaseNameController.text.trim()),
        port: PortNumber(port),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      final result = await _backupService.testConnection(testConfig);

      if (!mounted) return;

      result.fold(
        (_) {
          MessageModal.showSuccess(
            context,
            message: _t(
              'Conexao testada com sucesso!',
              'Connection tested successfully!',
            ),
          );
        },
        (failure) {
          final f = failure as Failure;
          final errorMessage = f.message.isNotEmpty
              ? f.message
              : _t(
                  'Erro desconhecido ao testar conexao',
                  'Unknown error testing connection',
                );

          MessageModal.showError(
            context,
            title: _t('Erro ao testar conexao', 'Error testing connection'),
            message: errorMessage,
          );
        },
      );
    } on Object catch (e, stackTrace) {
      if (!mounted) return;

      LoggerService.error('Erro ao testar conexão Sybase', e, stackTrace);

      final errorMessage = e.toString().replaceAll('Exception: ', '');

      MessageModal.showError(
        context,
        title: _t('Erro ao testar conexao', 'Error testing connection'),
        message: errorMessage.isNotEmpty
            ? errorMessage
            : _t('Erro desconhecido', 'Unknown error'),
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
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    final port = int.tryParse(_portController.text) ?? 2638;
    final config = SybaseConfig(
      id: widget.config?.id,
      name: _nameController.text.trim(),
      serverName: _serverNameController.text.trim(),
      databaseName: DatabaseName(_databaseNameController.text.trim()),
      port: PortNumber(port),
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
          const Icon(FluentIcons.server, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing
                  ? _t(
                      'Editar configuracao Sybase',
                      'Edit Sybase configuration',
                    )
                  : _t('Nova configuracao Sybase', 'New Sybase configuration'),
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
                  label: _t('Nome da configuracao', 'Configuration name'),
                  hint: _t('Ex: Producao Sybase', 'Ex: Production Sybase'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return _t('Nome e obrigatorio', 'Name is required');
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
                        label: _t(
                          'Nome do servidor (Engine Name)',
                          'Server name (Engine Name)',
                        ),
                        hint: _t(
                          'Ex: VL (nome do servico Sybase)',
                          'Ex: VL (Sybase service name)',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return _t(
                              'Engine Name e obrigatorio',
                              'Engine Name is required',
                            );
                          }
                          return null;
                        },
                        prefixIcon: const Icon(FluentIcons.server),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: NumericField(
                        controller: _portController,
                        label: _t('Porta', 'Port'),
                        hint: AppConstants.defaultSybasePort.toString(),
                        prefixIcon: FluentIcons.number_field,
                        minValue: 1,
                        maxValue: 65535,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return _t(
                              'Porta e obrigatoria',
                              'Port is required',
                            );
                          }
                          final port = int.tryParse(value);
                          if (port == null || port < 1 || port > 65535) {
                            return _t(
                              'Porta deve estar entre 1 e 65535',
                              'Port must be between 1 and 65535',
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _databaseNameController,
                  label: _t(
                    'Nome do banco de dados (DBN)',
                    'Database name (DBN)',
                  ),
                  hint: _t(
                    'Ex: VL (geralmente igual ao Engine Name)',
                    'Ex: VL (usually same as Engine Name)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return _t(
                        'Nome do banco de dados e obrigatorio',
                        'Database name is required',
                      );
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
                      const Icon(
                        FluentIcons.info,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _t(
                            'O Engine Name e DBN geralmente sao iguais ao nome do servico Sybase (ex: VL)',
                            'Engine Name and DBN are usually equal to Sybase service name (ex: VL)',
                          ),
                          style: FluentTheme.of(context).typography.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _usernameController,
                  label: _t('Usuario', 'Username'),
                  hint: _t('DBA ou usuario do Sybase', 'DBA or Sybase user'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return _t(
                        'Usuario e obrigatorio',
                        'Username is required',
                      );
                    }
                    return null;
                  },
                  prefixIcon: const Icon(FluentIcons.contact),
                ),
                const SizedBox(height: 16),
                PasswordField(controller: _passwordController),
                const SizedBox(height: 16),
                InfoLabel(
                  label: _t('Habilitado', 'Enabled'),
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
                  _t(
                    'Permitir uso desta configuracao em agendamentos',
                    'Allow this configuration in schedules',
                  ),
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
          label: _t('Testar conexao', 'Test connection'),
          icon: FluentIcons.check_mark,
          onPressed: _testConnection,
          isLoading: _isTestingConnection,
        ),
        SaveButton(onPressed: _save, isEditing: isEditing),
      ],
    );
  }
}
