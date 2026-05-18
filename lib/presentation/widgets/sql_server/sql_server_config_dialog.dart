import 'dart:async';

import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class SqlServerConfigDialog extends StatefulWidget {
  const SqlServerConfigDialog({super.key, this.config});

  final SqlServerConfig? config;

  static Future<SqlServerConfig?> show(
    BuildContext context, {
    SqlServerConfig? config,
  }) async {
    return showDialog<SqlServerConfig>(
      context: context,
      builder: (BuildContext context) => SqlServerConfigDialog(config: config),
    );
  }

  @override
  State<SqlServerConfigDialog> createState() => _SqlServerConfigDialogState();
}

class _SqlServerConfigDialogState extends State<SqlServerConfigDialog> {
  static const int _kDefaultSqlServerPort = 1433;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _serverController = TextEditingController();
  final TextEditingController _databaseController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '$_kDefaultSqlServerPort',
  );

  bool _useWindowsAuth = false;
  bool _isEnabled = true;
  bool _isTestingConnection = false;
  bool _isLoadingDatabases = false;
  List<String> _databases = <String>[];
  String? _selectedDatabase;

  late final String _configSessionId;
  late final ISqlServerBackupService _backupService;

  bool get isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    _configSessionId = widget.config?.id ?? const Uuid().v4();
    _backupService = getIt<ISqlServerBackupService>();

    if (widget.config != null) {
      final c = widget.config!;
      _nameController.text = c.name;
      _serverController.text = c.server;
      _databaseController.text = c.databaseValue;
      _usernameController.text = c.username;
      _passwordController.text = c.password;
      _portController.text = c.portValue.toString();
      _isEnabled = c.enabled;
      _useWindowsAuth = c.useWindowsAuth;
      _selectedDatabase = c.databaseValue;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
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
          const Icon(FluentIcons.database, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing
                  ? appLocaleString(
                      context,
                      'Editar configuração SQL Server',
                      'Edit SQL Server configuration',
                    )
                  : appLocaleString(
                      context,
                      'Nova configuração SQL Server',
                      'New SQL Server configuration',
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
              hint: 'Ex: Produção SQL Server',
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
            _buildServerPortFields(context),
            const SizedBox(height: 16),
            _buildDatabaseSection(context),
            const SizedBox(height: 16),
            InfoLabel(
              label: appLocaleString(
                context,
                'Tipo de autenticação',
                'Authentication type',
              ),
              child: ToggleSwitch(
                checked: _useWindowsAuth,
                onChanged: (bool value) {
                  setState(() {
                    _useWindowsAuth = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              appLocaleString(
                context,
                'Windows Authentication usa credenciais do Windows (integrated security)',
                'Windows Auth uses Windows credentials (integrated security)',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _usernameController,
              label: appLocaleString(context, 'Usuario', 'Username'),
              hint: 'sa ou usuário do SQL Server',
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  if (_useWindowsAuth) {
                    return null;
                  }
                  return appLocaleString(
                    context,
                    'Usuário é obrigatório',
                    'Username is required',
                  );
                }
                return null;
              },
              enabled: !_useWindowsAuth,
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
              enabled: !_useWindowsAuth,
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

  Widget _buildServerPortFields(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            controller: _serverController,
            label: appLocaleString(context, 'Servidor', 'Server'),
            hint: r'localhost ou IP\INSTANCIA',
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return appLocaleString(
                  context,
                  'Servidor é obrigatório',
                  'Server is required',
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
            hint: '$_kDefaultSqlServerPort',
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
                  'Nome do banco é obrigatório',
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
                      'Preencha servidor, porta, usuário e senha, depois clique em "Testar conexão" para carregar os bancos no dropdown',
                      'Fill server, port, username and password, then click "Test connection" to load databases in the dropdown',
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppDropdown<String>(
            label: appLocaleString(context, 'Banco de dados', 'Database'),
            value: _selectedDatabase,
            placeholder: Text(
              _isLoadingDatabases
                  ? appLocaleString(
                      context,
                      'Carregando bancos...',
                      'Loading databases...',
                    )
                  : _databases.isEmpty
                  ? appLocaleString(
                      context,
                      'Nenhum banco encontrado',
                      'No database found',
                    )
                  : appLocaleString(
                      context,
                      'Selecione o banco',
                      'Select database',
                    ),
            ),
            items: _databases.map((String db) {
              return ComboBoxItem<String>(value: db, child: Text(db));
            }).toList(),
            onChanged: _isLoadingDatabases || _databases.isEmpty
                ? null
                : (String? value) {
                    setState(() {
                      _selectedDatabase = value;
                      _databaseController.text = value ?? '';
                    });
                  },
          ),
        ),
        const SizedBox(width: 8),
        if (_isLoadingDatabases)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: SizedBox(
              width: 20,
              height: 20,
              child: ProgressRing(strokeWidth: 2),
            ),
          )
        else if (_databases.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: IconButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: _testConnection,
            ),
          ),
      ],
    );
  }

  Future<void> _testConnection() async {
    if (_serverController.text.trim().isEmpty ||
        _portController.text.trim().isEmpty ||
        (!_useWindowsAuth && _usernameController.text.trim().isEmpty) ||
        (!_useWindowsAuth && _passwordController.text.isEmpty)) {
      unawaited(
        FluentInfoBarFeedback.showWarning(
          context,
          message: appLocaleString(
            context,
            'Preencha servidor, porta, usuario e senha para testar',
            'Fill server, port, username and password to test',
          ),
        ),
      );
      return;
    }

    try {
      var probeStarted = false;
      final outcome =
          await TestConnectionRunner<SqlServerConfig>(
            validate: _validateSqlTestConnectionPort,
            buildConfig: _buildTempSqlServerConfigForTest,
            runTest: _runSqlServerTestPipeline,
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
        context.read<SqlServerConfigProvider>().recordConnectionTest(
          _configSessionId,
          success: outcome is TestConnectionSucceeded,
        );
      }
      _presentSqlTestConnectionOutcome(outcome);
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

  String? _validateSqlTestConnectionPort() {
    final port = int.tryParse(_portController.text.trim());
    if (port == null) {
      return appLocaleString(context, 'Porta invalida', 'Invalid port');
    }
    if (port < 1 || port > 65535) {
      return appLocaleString(
        context,
        'Porta invalida. Deve estar entre 1 e 65535.',
        'Invalid port. Must be between 1 and 65535.',
      );
    }
    return null;
  }

  SqlServerConfig _buildTempSqlServerConfigForTest() {
    final port = int.tryParse(_portController.text.trim())!;
    return SqlServerConfig(
      id: _configSessionId,
      name: 'temp',
      server: _serverController.text.trim(),
      port: PortNumber(port),
      database: DatabaseName('master'),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      useWindowsAuth: _useWindowsAuth,
    );
  }

  Future<TestConnectionOutcome> _runSqlServerTestPipeline(
    SqlServerConfig config,
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

    final connectionResult = await _backupService.testConnection(config);
    final success = connectionResult.getOrNull();
    if (success == null) {
      final failure = connectionResult.exceptionOrNull();
      return TestConnectionFailed(
        testConnectionUserMessage(
          failure,
          fallback: mUnknownTest,
        ),
      );
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

  void _presentSqlTestConnectionOutcome(TestConnectionOutcome outcome) {
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

    final sqlServerConfig = SqlServerConfig(
      id: _configSessionId,
      name: _nameController.text.trim(),
      server: _serverController.text.trim(),
      database: DatabaseName(database),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      port: PortNumber(portParsed),
      enabled: _isEnabled,
      useWindowsAuth: _useWindowsAuth,
      createdAt: widget.config?.createdAt,
      updatedAt: widget.config?.updatedAt,
    );
    Navigator.of(context).pop(sqlServerConfig);
  }
}
