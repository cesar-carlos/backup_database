import 'dart:async';

import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class PostgresConfigDialog extends StatefulWidget {
  const PostgresConfigDialog({super.key, this.config});

  final PostgresConfig? config;

  static Future<PostgresConfig?> show(
    BuildContext context, {
    PostgresConfig? config,
  }) async {
    return showDialog<PostgresConfig>(
      context: context,
      builder: (BuildContext context) => PostgresConfigDialog(config: config),
    );
  }

  @override
  State<PostgresConfigDialog> createState() => _PostgresConfigDialogState();
}

class _PostgresConfigDialogState extends State<PostgresConfigDialog> {
  static const int _kDefaultPostgresPort = 5432;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _databaseController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '$_kDefaultPostgresPort',
  );

  bool _isEnabled = true;
  bool _isTestingConnection = false;
  bool _isLoadingDatabases = false;
  List<String> _databases = <String>[];
  String? _selectedDatabase;

  late final String _configSessionId;
  late final IPostgresBackupService _backupService;

  bool get isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    _configSessionId = widget.config?.id ?? const Uuid().v4();
    _backupService = getIt<IPostgresBackupService>();

    if (widget.config != null) {
      final c = widget.config!;
      _nameController.text = c.name;
      _hostController.text = c.host;
      _databaseController.text = c.databaseValue;
      _usernameController.text = c.username;
      _passwordController.text = c.password;
      _portController.text = c.portValue.toString();
      _isEnabled = c.enabled;
      _selectedDatabase = c.databaseValue;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
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
                      'Editar configuração PostgreSQL',
                      'Edit PostgreSQL configuration',
                    )
                  : appLocaleString(
                      context,
                      'Nova configuração PostgreSQL',
                      'New PostgreSQL configuration',
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
              hint: 'Ex: Produção PostgreSQL',
              validator: (String? value) {
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
            _buildHostPortFields(context),
            const SizedBox(height: 16),
            _buildDatabaseSection(context),
            const SizedBox(height: 16),
            AppTextField(
              controller: _usernameController,
              label: appLocaleString(context, 'Usuário', 'Username'),
              hint: appLocaleString(
                context,
                'postgres ou usuário do PostgreSQL',
                'postgres or PostgreSQL user',
              ),
              validator: (String? value) {
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
            PasswordField(
              controller: _passwordController,
              hint: appLocaleString(
                context,
                'Senha do usuario',
                'User password',
              ),
            ),
            const SizedBox(height: 24),
            InfoLabel(
              label: appLocaleString(context, 'Habilitado', 'Enabled'),
              child: ToggleSwitch(
                checked: _isEnabled,
                onChanged: (bool value) {
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
                'Configuração ativa para uso em agendamentos',
                'Configuration active for schedules',
              ),
              style: FluentTheme.of(context).typography.caption,
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

  Widget _buildHostPortFields(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            controller: _hostController,
            label: appLocaleString(context, 'Host', 'Host'),
            hint: appLocaleString(
              context,
              'localhost ou IP',
              'localhost or IP',
            ),
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return appLocaleString(
                  context,
                  'Host é obrigatório',
                  'Host is required',
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
            hint: '$_kDefaultPostgresPort',
            prefixIcon: FluentIcons.number_field,
            minValue: 1,
            maxValue: 65535,
          ),
        ),
      ],
    );
  }

  Widget _buildDatabaseSection(BuildContext context) {
    if (_databases.isEmpty && !_isLoadingDatabases) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _databaseController,
            label: appLocaleString(
              context,
              'Nome do banco de dados',
              'Database name',
            ),
            hint: appLocaleString(
              context,
              'Digite ou clique em "Testar conexão" para carregar',
              'Type or click "Test connection" to load',
            ),
            validator: (String? value) {
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
                      'Preencha host, porta, usuário e senha, depois clique em "Testar conexão" para carregar os bancos no dropdown',
                      'Fill host, port, username and password, then click "Test connection" to load databases in the dropdown',
                    ),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_isLoadingDatabases) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: ProgressRing(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppDropdown<String>(
          label: appLocaleString(
            context,
            'Nome do banco de dados',
            'Database name',
          ),
          value: _selectedDatabase,
          placeholder: Text(
            appLocaleString(
              context,
              'Selecione um banco de dados',
              'Select a database',
            ),
          ),
          items: _databases.map((String db) {
            return ComboBoxItem<String>(value: db, child: Text(db));
          }).toList(),
          onChanged: (String? value) {
            setState(() {
              _selectedDatabase = value;
              if (value != null) {
                _databaseController.text = value;
              }
            });
          },
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: _databaseController,
          label: appLocaleString(
            context,
            'Nome do banco de dados (manual)',
            'Database name (manual)',
          ),
          hint: appLocaleString(
            context,
            'Digite o nome do banco de dados',
            'Enter database name',
          ),
          validator: (String? value) {
            if ((_selectedDatabase == null || _selectedDatabase!.isEmpty) &&
                (value == null || value.trim().isEmpty)) {
              return appLocaleString(
                context,
                'Selecione ou digite um nome de banco de dados',
                'Select or type a database name',
              );
            }
            return null;
          },
          prefixIcon: const Icon(FluentIcons.database),
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    if (_hostController.text.trim().isEmpty ||
        _portController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      unawaited(
        FluentInfoBarFeedback.showWarning(
          context,
          message: appLocaleString(
            context,
            'Preencha host, porta, usuario e senha para testar',
            'Fill host, port, username and password to test',
          ),
        ),
      );
      return;
    }

    try {
      var probeStarted = false;
      final outcome =
          await TestConnectionRunner<PostgresConfig>(
            validate: _validatePostgresTestConnectionPort,
            buildConfig: _buildTempPostgresConfigForTest,
            runTest: _runPostgresTestPipeline,
          ).execute(
            afterValidation: () {
              if (!mounted) {
                return;
              }
              setState(() {
                _isTestingConnection = true;
                _isLoadingDatabases = true;
                _databases = <String>[];
                _selectedDatabase = null;
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
        context.read<PostgresConfigProvider>().recordConnectionTest(
          _configSessionId,
          success: outcome is TestConnectionSucceeded,
        );
      }
      _presentPostgresTestConnectionOutcome(outcome);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDatabases = false;
          _isTestingConnection = false;
        });
        unawaited(MessageModal.showError(context, message: e.toString()));
      }
    }
  }

  String? _validatePostgresTestConnectionPort() {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      return appLocaleString(
        context,
        'Porta invalida. Deve estar entre 1 e 65535.',
        'Invalid port. Must be between 1 and 65535.',
      );
    }
    return null;
  }

  PostgresConfig _buildTempPostgresConfigForTest() {
    final port = int.tryParse(_portController.text.trim())!;
    return PostgresConfig(
      id: _configSessionId,
      name: 'temp',
      host: _hostController.text.trim(),
      port: PortNumber(port),
      database: DatabaseName('postgres'),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  Future<TestConnectionOutcome> _runPostgresTestPipeline(
    PostgresConfig config,
  ) async {
    final mUnknownTest = appLocaleString(
      context,
      'Erro desconhecido ao testar conexão',
      'Unknown error testing connection',
    );
    final mConnFailed = appLocaleString(
      context,
      'Conexão falhou',
      'Connection failed',
    );
    final mUnknownShort = appLocaleString(
      context,
      'Erro desconhecido',
      'Unknown error',
    );
    final mListPrefix = appLocaleString(
      context,
      'Conexão OK, mas erro ao listar bancos: ',
      'Connection OK, but error listing databases: ',
    );
    final psqlToolMsg = ToolPathHelp.buildMessage('psql');

    final connectionResult = await _backupService.testConnection(config);
    final success = connectionResult.getOrNull();
    if (success == null) {
      final failure = connectionResult.exceptionOrNull();
      var msg = testConnectionUserMessage(
        failure,
        fallback: mUnknownTest,
      );
      final msgLower = msg.toLowerCase();
      if (ToolPathHelp.isToolNotFoundError(msgLower, 'psql')) {
        msg = psqlToolMsg;
      }
      return TestConnectionFailed(msg);
    }
    if (!success) {
      return TestConnectionFailed(mConnFailed);
    }

    final databasesResult = await _backupService.listDatabases(config: config);
    final databases = databasesResult.getOrNull();
    if (databases != null) {
      return TestConnectionSucceeded(databases: databases);
    }
    final listFailure = databasesResult.exceptionOrNull();
    final detail = testConnectionUserMessage(
      listFailure,
      fallback: mUnknownShort,
    );
    return TestConnectionSucceeded(
      listWarning: '$mListPrefix$detail',
    );
  }

  void _presentPostgresTestConnectionOutcome(TestConnectionOutcome outcome) {
    switch (outcome) {
      case TestConnectionSucceeded(
        :final databases,
        :final listWarning,
      ):
        setState(() {
          _databases = databases;
          _isLoadingDatabases = false;
          _isTestingConnection = false;
          if (databases.length == 1) {
            _selectedDatabase = databases.first;
            _databaseController.text = databases.first;
          }
        });
        if (listWarning != null) {
          unawaited(
            FluentInfoBarFeedback.showWarning(context, message: listWarning),
          );
          return;
        }
        unawaited(
          FluentInfoBarFeedback.showInfo(
            context,
            message: databases.isEmpty
                ? appLocaleString(
                    context,
                    'Conexão OK, mas nenhum banco encontrado',
                    'Connection OK, but no database found',
                  )
                : appLocaleString(
                    context,
                    'Conexão OK! ${databases.length} banco(s) encontrado(s). Selecione um no dropdown.',
                    'Connection OK! ${databases.length} database(s) found. Select one from dropdown.',
                  ),
          ),
        );
      case TestConnectionFailed(:final message):
        setState(() {
          _isLoadingDatabases = false;
          _isTestingConnection = false;
        });
        unawaited(
          MessageModal.showError(
            context,
            title: appLocaleString(
              context,
              'Erro ao testar conexão',
              'Error testing connection',
            ),
            message: message,
          ),
        );
    }
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final portParsed = int.tryParse(_portController.text.trim());
    if (portParsed == null) {
      unawaited(
        MessageModal.showError(
          context,
          message: appLocaleString(context, 'Porta invalida', 'Invalid port'),
        ),
      );
      return;
    }

    final database = _selectedDatabase ?? _databaseController.text.trim();
    if (database.isEmpty) {
      unawaited(
        MessageModal.showError(
          context,
          message: appLocaleString(
            context,
            'Selecione ou informe um banco de dados',
            'Select or inform a database',
          ),
        ),
      );
      return;
    }

    final postgresConfig = PostgresConfig(
      id: _configSessionId,
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: PortNumber(portParsed),
      database: DatabaseName(database),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      enabled: _isEnabled,
      createdAt: widget.config?.createdAt,
      updatedAt: widget.config?.updatedAt,
    );
    Navigator.of(context).pop(postgresConfig);
  }
}
