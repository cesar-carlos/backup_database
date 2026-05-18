import 'dart:async';

import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

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
  bool _isReplicationEnvironment = false;
  bool _isTestingConnection = false;

  late final String _configSessionId;
  late final ISybaseBackupService _backupService;

  bool get isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    _configSessionId = widget.config?.id ?? const Uuid().v4();
    _backupService = widget.backupService;

    if (widget.config != null) {
      _nameController.text = widget.config!.name;
      _serverNameController.text = widget.config!.serverName;
      _databaseNameController.text = widget.config!.databaseNameValue;
      _portController.text = widget.config!.portValue.toString();
      _usernameController.text = widget.config!.username;
      _passwordController.text = widget.config!.password;
      _isEnabled = widget.config!.enabled;
      _isReplicationEnvironment = widget.config!.isReplicationEnvironment;
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

    if (!mounted) {
      return;
    }

    try {
      var probeStarted = false;
      final mSuccess = appLocaleString(
        context,
        'Conexão testada com sucesso!',
        'Connection tested successfully!',
      );
      final mUnknownConn = appLocaleString(
        context,
        'Erro desconhecido ao testar conexão',
        'Unknown error testing connection',
      );
      final mErrTitle = appLocaleString(
        context,
        'Erro ao testar conexão',
        'Error testing connection',
      );

      final outcome =
          await TestConnectionRunner<SybaseConfig>(
            validate: _validateSybaseTestPort,
            buildConfig: _buildSybaseTestConfig,
            runTest: (SybaseConfig config) async {
              final result = await _backupService.testConnection(config);
              final ok = result.getOrNull();
              if (ok != null && ok) {
                return const TestConnectionSucceeded();
              }
              if (ok != null && !ok) {
                return TestConnectionFailed(mUnknownConn);
              }
              final failure = result.exceptionOrNull();
              return TestConnectionFailed(
                testConnectionUserMessage(
                  failure,
                  fallback: mUnknownConn,
                ),
              );
            },
          ).execute(
            afterValidation: () {
              if (!mounted) {
                return;
              }
              setState(() {
                _isTestingConnection = true;
              });
            },
            onProbeStarted: () {
              probeStarted = true;
            },
          );
      if (!mounted) {
        return;
      }
      if (probeStarted) {
        context.read<SybaseConfigProvider>().recordConnectionTest(
          _configSessionId,
          success: outcome is TestConnectionSucceeded,
        );
      }
      switch (outcome) {
        case TestConnectionSucceeded():
          unawaited(
            FluentInfoBarFeedback.showSuccess(context, message: mSuccess),
          );
        case TestConnectionFailed(:final message):
          final rawMessage = message.isNotEmpty ? message : mUnknownConn;
          unawaited(
            MessageModal.showError(
              context,
              title: mErrTitle,
              message: rawMessage,
            ),
          );
      }
    } on Object catch (e, stackTrace) {
      if (!mounted) {
        return;
      }

      LoggerService.error('Erro ao testar conexão Sybase', e, stackTrace);

      final errorMessage = e.toString().replaceAll('Exception: ', '');

      unawaited(
        MessageModal.showError(
          context,
          title: appLocaleString(
            context,
            'Erro ao testar conexão',
            'Error testing connection',
          ),
          message: errorMessage.isNotEmpty
              ? errorMessage
              : appLocaleString(context, 'Erro desconhecido', 'Unknown error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  String? _validateSybaseTestPort() {
    final port =
        int.tryParse(_portController.text.trim()) ??
        AppConstants.defaultSybasePort;
    if (port < 1 || port > 65535) {
      return appLocaleString(
        context,
        'Porta invalida. Deve estar entre 1 e 65535.',
        'Invalid port. Must be between 1 and 65535.',
      );
    }
    return null;
  }

  SybaseConfig _buildSybaseTestConfig() {
    final port =
        int.tryParse(_portController.text.trim()) ??
        AppConstants.defaultSybasePort;
    return SybaseConfig(
      id: _configSessionId,
      name: _nameController.text.trim(),
      serverName: _serverNameController.text.trim(),
      databaseName: DatabaseName(_databaseNameController.text.trim()),
      port: PortNumber(port),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      isReplicationEnvironment: _isReplicationEnvironment,
    );
  }

  void _save() {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    final port = int.tryParse(_portController.text) ?? 2638;
    final config = SybaseConfig(
      id: _configSessionId,
      name: _nameController.text.trim(),
      serverName: _serverNameController.text.trim(),
      databaseName: DatabaseName(_databaseNameController.text.trim()),
      port: PortNumber(port),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      enabled: _isEnabled,
      isReplicationEnvironment: _isReplicationEnvironment,
      createdAt: widget.config?.createdAt,
      updatedAt: widget.config?.updatedAt,
    );

    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return DatabaseConfigDialogShell(
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
                  ? appLocaleString(
                      context,
                      'Editar configuração Sybase',
                      'Edit Sybase configuration',
                    )
                  : appLocaleString(
                      context,
                      'Nova configuração Sybase',
                      'New Sybase configuration',
                    ),
              style: FluentTheme.of(context).typography.title,
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _nameController,
              label: appLocaleString(
                context,
                'Nome da configuração',
                'Configuration name',
              ),
              hint: appLocaleString(
                context,
                'Ex: Produção Sybase',
                'Ex: Production Sybase',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return appLocaleString(
                    context,
                    'Nome é obrigatório',
                    'Name is required',
                  );
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
                    label: appLocaleString(
                      context,
                      'Nome do servidor (Engine Name)',
                      'Server name (Engine Name)',
                    ),
                    hint: appLocaleString(
                      context,
                      'Ex: VL (nome do servico Sybase)',
                      'Ex: VL (Sybase service name)',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return appLocaleString(
                          context,
                          'Engine Name é obrigatório',
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
                    label: appLocaleString(context, 'Porta', 'Port'),
                    hint: AppConstants.defaultSybasePort.toString(),
                    prefixIcon: FluentIcons.number_field,
                    minValue: 1,
                    maxValue: 65535,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return appLocaleString(
                          context,
                          'Porta e obrigatoria',
                          'Port is required',
                        );
                      }
                      final port = int.tryParse(value);
                      if (port == null || port < 1 || port > 65535) {
                        return appLocaleString(
                          context,
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
              label: appLocaleString(
                context,
                'Nome do banco de dados (DBN)',
                'Database name (DBN)',
              ),
              hint: appLocaleString(
                context,
                'Ex: VL (geralmente igual ao Engine Name)',
                'Ex: VL (usually same as Engine Name)',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return appLocaleString(
                    context,
                    'Nome do banco de dados é obrigatório',
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
                      appLocaleString(
                        context,
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
              label: appLocaleString(context, 'Usuario', 'Username'),
              hint: appLocaleString(
                context,
                'DBA ou usuario do Sybase',
                'DBA or Sybase user',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return appLocaleString(
                    context,
                    'Usuário é obrigatório',
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
              label: appLocaleString(context, 'Habilitado', 'Enabled'),
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
              appLocaleString(
                context,
                'Permitir uso desta configuração em agendamentos',
                'Allow this configuration in schedules',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: appLocaleString(
                context,
                'Ambiente de replicação (SQL Remote, MobiLink)',
                'Replication environment (SQL Remote, MobiLink)',
              ),
              child: ToggleSwitch(
                checked: _isReplicationEnvironment,
                onChanged: (value) {
                  setState(() {
                    _isReplicationEnvironment = value;
                  });
                },
              ),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    FluentIcons.info,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appLocaleString(
                        context,
                        'Quando ativado, bloqueia backup de log com modo '
                            '"Truncar" (TRUNCATE). Use "Renomear" ou "Apenas" '
                            'para ambientes com SQL Remote ou MobiLink.',
                        'When enabled, blocks log backup with "Truncate" '
                            'mode (TRUNCATE). Use "Rename" or "Only" for '
                            'environments with SQL Remote or MobiLink.',
                      ),
                      style: FluentTheme.of(context).typography.caption,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      dialogActions: [
        const CancelButton(),
        ActionButton(
          label: appLocaleString(context, 'Testar conexão', 'Test connection'),
          icon: FluentIcons.check_mark,
          onPressed: _testConnection,
          isLoading: _isTestingConnection,
        ),
        SaveButton(onPressed: _save, isEditing: isEditing),
      ],
      onSubmitIntent: _save,
    );
  }
}
