import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum DatabaseType { sqlServer, sybase, postgresql }

class SqlServerConfigDialog extends StatefulWidget {
  const SqlServerConfigDialog({
    super.key,
    this.config,
    this.initialType = DatabaseType.sqlServer,
  });
  final SqlServerConfig? config;
  final DatabaseType initialType;

  static Future<Object?> show(
    BuildContext context, {
    SqlServerConfig? config,
    DatabaseType initialType = DatabaseType.sqlServer,
  }) async {
    return showDialog<Object>(
      context: context,
      builder: (context) =>
          SqlServerConfigDialog(config: config, initialType: initialType),
    );
  }

  @override
  State<SqlServerConfigDialog> createState() => _SqlServerConfigDialogState();
}

class _SqlServerConfigDialogState extends State<SqlServerConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverController = TextEditingController();
  final _hostController = TextEditingController();
  final _databaseController = TextEditingController();
  final _databaseNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '1433');

  DatabaseType _selectedType = DatabaseType.sqlServer;
  bool _useWindowsAuth = false;
  bool _isEnabled = true;
  bool _isTestingConnection = false;
  bool _isLoadingDatabases = false;
  List<String> _databases = [];
  String? _selectedDatabase;

  late final ISqlServerBackupService _backupService;
  late final ISybaseBackupService _sybaseBackupService;
  late final IPostgresBackupService _postgresBackupService;

  bool get isEditing => widget.config != null;

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  void initState() {
    super.initState();
    _backupService = getIt<ISqlServerBackupService>();
    _sybaseBackupService = getIt<ISybaseBackupService>();
    _postgresBackupService = getIt<IPostgresBackupService>();

    if (widget.initialType != DatabaseType.sqlServer) {
      _selectedType = widget.initialType;
    } else if (widget.config != null) {
      if (widget.config!.portValue == 2638 ||
          widget.config!.databaseValue.toLowerCase().endsWith('.db')) {
        _selectedType = DatabaseType.sybase;
      } else {
        _selectedType = DatabaseType.sqlServer;
      }
    } else {
      _selectedType = widget.initialType;
    }

    if (widget.config != null) {
      _nameController.text = widget.config!.name;

      if (_selectedType == DatabaseType.postgresql) {
        _hostController.text = widget.config!.server;
      } else {
        _serverController.text = widget.config!.server;
      }

      _databaseController.text = widget.config!.databaseValue;
      _usernameController.text = widget.config!.username;
      _passwordController.text = widget.config!.password;
      _portController.text = widget.config!.portValue.toString();
      _isEnabled = widget.config!.enabled;
      _useWindowsAuth = widget.config!.useWindowsAuth;
      _selectedDatabase = widget.config!.databaseValue;

      if (_selectedType == DatabaseType.sybase) {
        _databaseNameController.text = widget.config!.databaseValue;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    _hostController.dispose();
    _databaseController.dispose();
    _databaseNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onTypeChanged(DatabaseType? type) {
    if (type != null && type != _selectedType) {
      setState(() {
        _selectedType = type;
        _databases = [];
        _selectedDatabase = null;
        _databaseController.clear();
        _hostController.clear();
        _serverController.clear();

        if (type == DatabaseType.sqlServer) {
          _portController.text = '1433';
        } else if (type == DatabaseType.sybase) {
          _portController.text = '2638';
        } else if (type == DatabaseType.postgresql) {
          _portController.text = '5432';
        }
      });
    }
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
          Icon(
            _selectedType == DatabaseType.sqlServer
                ? FluentIcons.database
                : FluentIcons.server,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing
                  ? _t('Editar configuração', 'Edit configuration')
                  : _t(
                      'Nova configuração de banco de dados',
                      'New database configuration',
                    ),
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
                AppDropdown<DatabaseType>(
                  label: _t('Tipo de banco de dados', 'Database type'),
                  value: _selectedType,
                  placeholder: Text(
                    _t('Tipo de banco de dados', 'Database type'),
                  ),
                  items: const [
                    ComboBoxItem(
                      value: DatabaseType.sqlServer,
                      child: Text('SQL Server'),
                    ),
                    ComboBoxItem(
                      value: DatabaseType.sybase,
                      child: Text('Sybase SQL Anywhere'),
                    ),
                    ComboBoxItem(
                      value: DatabaseType.postgresql,
                      child: Text('PostgreSQL'),
                    ),
                  ],
                  onChanged: isEditing
                      ? null
                      : (value) {
                          if (value != null) {
                            _onTypeChanged(value);
                          }
                        },
                ),
                const SizedBox(height: 16),

                AppTextField(
                  controller: _nameController,
                  label: _t('Nome da configuração', 'Configuration name'),
                  hint: _selectedType == DatabaseType.sqlServer
                      ? 'Ex: Produção SQL Server'
                      : _selectedType == DatabaseType.postgresql
                      ? 'Ex: Produção PostgreSQL'
                      : 'Ex: Produção Sybase',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return _t('Nome é obrigatório', 'Name is required');
                    }
                    return null;
                  },
                  prefixIcon: const Icon(FluentIcons.tag),
                ),
                const SizedBox(height: 16),

                if (_selectedType == DatabaseType.sqlServer)
                  _buildSqlServerFields(context)
                else if (_selectedType == DatabaseType.sybase)
                  _buildSybaseFields(context)
                else if (_selectedType == DatabaseType.postgresql)
                  _buildPostgresFields(context),

                if (_selectedType == DatabaseType.sqlServer) ...[
                  const SizedBox(height: 16),
                  InfoLabel(
                    label: _t('Tipo de autenticação', 'Authentication type'),
                    child: ToggleSwitch(
                      checked: _useWindowsAuth,
                      onChanged: (value) {
                        setState(() {
                          _useWindowsAuth = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t(
                      'Windows Authentication usa credenciais do Windows (integrated security)',
                      'Windows Auth uses Windows credentials (integrated security)',
                    ),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 16),

                AppTextField(
                  controller: _usernameController,
                  label: _t('Usuario', 'Username'),
                  hint: _selectedType == DatabaseType.sqlServer
                      ? 'sa ou usuário do SQL Server'
                      : _selectedType == DatabaseType.postgresql
                      ? 'postgres ou usuário do PostgreSQL'
                      : 'DBA ou usuário do Sybase',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      if (_selectedType == DatabaseType.sqlServer &&
                          _useWindowsAuth) {
                        return null;
                      }
                      return _t(
                        'Usuário é obrigatório',
                        'Username is required',
                      );
                    }
                    return null;
                  },
                  enabled:
                      _selectedType != DatabaseType.sqlServer ||
                      !_useWindowsAuth,
                  prefixIcon: const Icon(FluentIcons.contact),
                ),
                const SizedBox(height: 16),

                PasswordField(
                  controller: _passwordController,
                  hint: _t('Senha do usuario', 'User password'),
                  enabled:
                      _selectedType != DatabaseType.sqlServer ||
                      !_useWindowsAuth,
                ),
                const SizedBox(height: 24),

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
                    'Configuração ativa para uso em agendamentos',
                    'Configuration active for schedules',
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
          label: _t('Testar conexão', 'Test connection'),
          icon: FluentIcons.check_mark,
          onPressed: _testConnection,
          isLoading: _isTestingConnection,
        ),
        SaveButton(onPressed: _save, isEditing: isEditing),
      ],
    );
  }

  Widget _buildSqlServerFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AppTextField(
                controller: _serverController,
                label: _t('Servidor', 'Server'),
                hint: r'localhost ou IP\INSTANCIA',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _t('Servidor é obrigatório', 'Server is required');
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
                hint: '1433',
                prefixIcon: FluentIcons.number_field,
                minValue: 1,
                maxValue: 65535,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_databases.isEmpty && !_isLoadingDatabases)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _databaseController,
                label: _t('Nome do banco de dados', 'Database name'),
                hint: _t(
                  'Digite ou clique em "Testar conexão" para carregar',
                  'Type or click "Test connection" to load',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _t(
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
                        _t(
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
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppDropdown<String>(
                  label: _t('Banco de dados', 'Database'),
                  value: _selectedDatabase,
                  placeholder: Text(
                    _isLoadingDatabases
                        ? _t('Carregando bancos...', 'Loading databases...')
                        : _databases.isEmpty
                        ? _t('Nenhum banco encontrado', 'No database found')
                        : _t('Selecione o banco', 'Select database'),
                  ),
                  items: _databases.map((db) {
                    return ComboBoxItem<String>(value: db, child: Text(db));
                  }).toList(),
                  onChanged: _isLoadingDatabases || _databases.isEmpty
                      ? null
                      : (value) {
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
          ),
      ],
    );
  }

  Widget _buildSybaseFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AppTextField(
                controller: _serverController,
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
                label: _t('Porta', 'Port'),
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
          label: _t('Nome do banco de dados (DBN)', 'Database name (DBN)'),
          hint: _t(
            'Ex: VL (geralmente igual ao Engine Name)',
            'Ex: VL (usually the same as Engine Name)',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _t(
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
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(FluentIcons.info, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(
                    'O Engine Name e DBN geralmente sao iguais ao nome do servico Sybase (ex: VL)',
                    'Engine Name and DBN are usually the same as the Sybase service name (ex: VL)',
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

  Widget _buildPostgresFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AppTextField(
                controller: _hostController,
                label: _t('Host', 'Host'),
                hint: _t('localhost ou IP', 'localhost or IP'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _t('Host é obrigatório', 'Host is required');
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
                hint: '5432',
                prefixIcon: FluentIcons.number_field,
                minValue: 1,
                maxValue: 65535,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_databases.isEmpty && !_isLoadingDatabases)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _databaseController,
                label: _t('Nome do banco de dados', 'Database name'),
                hint:
                    "Digite ou clique em _t('Testar conexão', 'Test connection') para carregar",
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _t(
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
                        _t(
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
          )
        else
          _isLoadingDatabases
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: ProgressRing(),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppDropdown<String>(
                      label: _t('Nome do banco de dados', 'Database name'),
                      value: _selectedDatabase,
                      placeholder: Text(
                        _t(
                          'Selecione um banco de dados',
                          'Select a database',
                        ),
                      ),
                      items: _databases.map((db) {
                        return ComboBoxItem<String>(value: db, child: Text(db));
                      }).toList(),
                      onChanged: (value) {
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
                      label: _t(
                        'Nome do banco de dados (manual)',
                        'Database name (manual)',
                      ),
                      hint: _t(
                        'Digite o nome do banco de dados',
                        'Enter database name',
                      ),
                      validator: (value) {
                        if ((_selectedDatabase == null ||
                                _selectedDatabase!.isEmpty) &&
                            (value == null || value.trim().isEmpty)) {
                          return _t(
                            'Selecione ou digite um nome de banco de dados',
                            'Select or type a database name',
                          );
                        }
                        return null;
                      },
                      prefixIcon: const Icon(FluentIcons.database),
                    ),
                  ],
                ),
      ],
    );
  }

  Future<void> _testConnection() async {
    if (_selectedType == DatabaseType.sybase) {
      if (_serverController.text.trim().isEmpty ||
          _portController.text.trim().isEmpty ||
          _databaseNameController.text.trim().isEmpty ||
          _usernameController.text.trim().isEmpty ||
          _passwordController.text.isEmpty) {
        MessageModal.showWarning(
          context,
          message: _t(
            'Preencha nome da maquina, porta, nome do banco de dados, usuario e senha para testar',
            'Fill server name, port, database name, username and password to test',
          ),
        );
        return;
      }

      setState(() {
        _isTestingConnection = true;
      });

      try {
        final port = int.tryParse(_portController.text.trim());
        if (port == null || port < 1 || port > 65535) {
          throw Exception(
            _t(
              'Porta invalida. Deve estar entre 1 e 65535.',
              'Invalid port. Must be between 1 and 65535.',
            ),
          );
        }

        final testConfig = SybaseConfig(
          name: 'temp',
          serverName: _serverController.text.trim(),
          databaseName: DatabaseName(_databaseNameController.text.trim()),
          port: PortNumber(port),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );

        final connectionResult = await _sybaseBackupService.testConnection(
          testConfig,
        );

        if (!mounted) return;

        connectionResult.fold(
          (_) {
            MessageModal.showSuccess(
              context,
              message: _t(
                'Conexão testada com sucesso!',
                'Connection tested successfully!',
              ),
            );
          },
          (failure) {
            final f = failure as Failure;
            final errorMessage = f.message.isNotEmpty
                ? f.message
                : _t(
                    'Erro desconhecido ao testar conexão',
                    'Unknown error testing connection',
                  );

            MessageModal.showError(
              context,
              title: _t('Erro ao testar conexão', 'Error testing connection'),
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
          title: _t('Erro ao testar conexão', 'Error testing connection'),
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
      return;
    }

    if (_selectedType == DatabaseType.postgresql) {
      if (_hostController.text.trim().isEmpty ||
          _portController.text.trim().isEmpty ||
          _usernameController.text.trim().isEmpty ||
          _passwordController.text.isEmpty) {
        MessageModal.showWarning(
          context,
          message: _t(
            'Preencha host, porta, usuario e senha para testar',
            'Fill host, port, username and password to test',
          ),
        );
        return;
      }

      setState(() {
        _isTestingConnection = true;
        _isLoadingDatabases = true;
        _databases = [];
        _selectedDatabase = null;
      });

      try {
        final port = int.tryParse(_portController.text);
        if (port == null || port < 1 || port > 65535) {
          throw Exception(
            _t(
              'Porta invalida. Deve estar entre 1 e 65535.',
              'Invalid port. Must be between 1 and 65535.',
            ),
          );
        }

        final tempConfig = PostgresConfig(
          name: 'temp',
          host: _hostController.text.trim(),
          port: PortNumber(port),
          database: DatabaseName('postgres'),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );

        final connectionResult = await _postgresBackupService.testConnection(
          tempConfig,
        );

        await connectionResult.fold(
          (success) async {
            final databasesResult = await _postgresBackupService.listDatabases(
              config: tempConfig,
            );

            await databasesResult.fold(
              (databases) async {
                if (mounted) {
                  setState(() {
                    _databases = databases;
                    _isLoadingDatabases = false;
                    _isTestingConnection = false;

                    if (databases.length == 1) {
                      _selectedDatabase = databases.first;
                      _databaseController.text = databases.first;
                    }
                  });

                  MessageModal.showInfo(
                    context,
                    message: databases.isEmpty
                        ? _t(
                            'Conexão OK, mas nenhum banco encontrado',
                            'Connection OK, but no database found',
                          )
                        : _t(
                            'Conexão OK! ${databases.length} banco(s) encontrado(s). Selecione um no dropdown.',
                            'Connection OK! ${databases.length} database(s) found. Select one from dropdown.',
                          ),
                  );
                }
              },
              (failure) async {
                if (mounted) {
                  setState(() {
                    _isLoadingDatabases = false;
                    _isTestingConnection = false;
                  });
                  final message = failure is Failure
                      ? failure.message
                      : failure.toString();
                  MessageModal.showWarning(
                    context,
                    message: _t(
                      'Conexão OK, mas erro ao listar bancos: $message',
                      'Connection OK, but error listing databases: $message',
                    ),
                  );
                }
              },
            );
          },
          (failure) async {
            if (mounted) {
              setState(() {
                _isLoadingDatabases = false;
                _isTestingConnection = false;
              });
              var message = failure is Failure
                  ? failure.message
                  : failure.toString();

              final messageLower = message.toLowerCase();
              if ((messageLower.contains('psql') ||
                      messageLower.contains("'psql'")) &&
                  (messageLower.contains('não é reconhecido') ||
                      messageLower.contains('não reconhecido') ||
                      messageLower.contains('não reconhecido como') ||
                      messageLower.contains('command not found') ||
                      messageLower.contains('não encontrado'))) {
                message =
                    'psql não encontrado no PATH do sistema.\n\n'
                    'INSTRUÇÕES PARA ADICIONAR AO PATH:\n\n'
                    '1. Localize a pasta bin do PostgreSQL instalado\n'
                    '   (geralmente: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
                    '2. Adicione ao PATH do Windows:\n'
                    '   - Pressione Win + X e selecione "Sistema"\n'
                    '   - Clique em "Configurações avançadas do sistema"\n'
                    '   - Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
                    '   - Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
                    '   - Clique em "Novo" e adicione o caminho completo da pasta bin\n'
                    '   - Clique em "OK" em todas as janelas\n\n'
                    '3. Reinicie o aplicativo de backup\n\n'
                    r'Consulte: docs\path_setup.md para mais detalhes.';
              }

              MessageModal.showError(
                context,
                title: _t('Erro ao testar conexão', 'Error testing connection'),
                message: message,
              );
            }
          },
        );
      } on Object catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingDatabases = false;
            _isTestingConnection = false;
          });
          MessageModal.showError(context, message: e.toString());
        }
      }
      return;
    }

    if (_serverController.text.trim().isEmpty ||
        _portController.text.trim().isEmpty ||
        (!_useWindowsAuth && _usernameController.text.trim().isEmpty) ||
        (!_useWindowsAuth && _passwordController.text.isEmpty)) {
      MessageModal.showWarning(
        context,
        message: _t(
          'Preencha servidor, porta, usuario e senha para testar',
          'Fill server, port, username and password to test',
        ),
      );
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _isLoadingDatabases = true;
      _databases = [];
      _selectedDatabase = null;
    });

    try {
      final port = int.tryParse(_portController.text);
      if (port == null) {
        throw Exception(_t('Porta invalida', 'Invalid port'));
      }

      final tempConfig = SqlServerConfig(
        name: 'temp',
        server: _serverController.text.trim(),
        port: PortNumber(port),
        database: DatabaseName('master'),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        useWindowsAuth: _useWindowsAuth,
      );

      final connectionResult = await _backupService.testConnection(tempConfig);

      await connectionResult.fold(
        (success) async {
          if (!success) {
            throw Exception(_t('Conexão falhou', 'Connection failed'));
          }

          final databasesResult = await _backupService.listDatabases(
            config: tempConfig,
          );

          await databasesResult.fold(
            (databases) async {
              if (mounted) {
                setState(() {
                  _databases = databases;
                  _isLoadingDatabases = false;
                  _isTestingConnection = false;

                  if (databases.length == 1) {
                    _selectedDatabase = databases.first;
                    _databaseController.text = databases.first;
                  }
                });

                MessageModal.showInfo(
                  context,
                  message: databases.isEmpty
                      ? _t(
                          'Conexão OK, mas nenhum banco encontrado',
                          'Connection OK, but no database found',
                        )
                      : _t(
                          'Conexão OK! ${databases.length} banco(s) encontrado(s). Selecione um no dropdown.',
                          'Connection OK! ${databases.length} database(s) found. Select one from dropdown.',
                        ),
                );
              }
            },
            (failure) async {
              if (mounted) {
                setState(() {
                  _isLoadingDatabases = false;
                  _isTestingConnection = false;
                });
                final message = failure is Failure
                    ? failure.message
                    : failure.toString();
                MessageModal.showWarning(
                  context,
                  message: _t(
                    'Conexão OK, mas erro ao listar bancos: $message',
                    'Connection OK, but error listing databases: $message',
                  ),
                );
              }
            },
          );
        },
        (failure) async {
          if (mounted) {
            setState(() {
              _isLoadingDatabases = false;
              _isTestingConnection = false;
            });
            final message = failure is Failure
                ? failure.message
                : failure.toString();
            MessageModal.showError(
              context,
              title: _t('Erro ao testar conexão', 'Error testing connection'),
              message: message,
            );
          }
        },
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDatabases = false;
          _isTestingConnection = false;
        });
        MessageModal.showError(context, message: e.toString());
      }
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final port = int.parse(_portController.text);
    final database = _selectedDatabase ?? _databaseController.text.trim();

    if (_selectedType == DatabaseType.sqlServer && database.isEmpty) {
      MessageModal.showError(
        context,
        message: _t(
          'Selecione ou informe um banco de dados',
          'Select or inform a database',
        ),
      );
      return;
    }

    if (_selectedType == DatabaseType.sybase &&
        _databaseNameController.text.trim().isEmpty) {
      MessageModal.showError(
        context,
        message: _t('Informe o nome do banco de dados', 'Inform database name'),
      );
      return;
    }

    if (_selectedType == DatabaseType.postgresql) {
      final database = _selectedDatabase ?? _databaseController.text.trim();
      if (database.isEmpty) {
        MessageModal.showError(
          context,
          message: _t(
            'Selecione ou informe um banco de dados',
            'Select or inform a database',
          ),
        );
        return;
      }

      final postgresConfig = PostgresConfig(
        id: widget.config?.id,
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: PortNumber(port),
        database: DatabaseName(database),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        enabled: _isEnabled,
        createdAt: widget.config?.createdAt,
        updatedAt: widget.config?.updatedAt,
      );
      Navigator.of(context).pop(postgresConfig);
      return;
    }

    if (_selectedType == DatabaseType.sybase) {
      final sybaseConfig = SybaseConfig(
        id: widget.config?.id,
        name: _nameController.text.trim(),
        serverName: _serverController.text.trim(),
        databaseName: DatabaseName(_databaseNameController.text.trim()),
        port: PortNumber(port),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        enabled: _isEnabled,
        createdAt: widget.config?.createdAt,
        updatedAt: widget.config?.updatedAt,
      );
      Navigator.of(context).pop(sybaseConfig);
    } else {
      final sqlServerConfig = SqlServerConfig(
        id: widget.config?.id,
        name: _nameController.text.trim(),
        server: _serverController.text.trim(),
        database: DatabaseName(database),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        port: PortNumber(port),
        enabled: _isEnabled,
        useWindowsAuth: _useWindowsAuth,
        createdAt: widget.config?.createdAt,
        updatedAt: widget.config?.updatedAt,
      );
      Navigator.of(context).pop(sqlServerConfig);
    }
  }
}
