import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/sql_server_config.dart';
import '../../../domain/entities/sybase_config.dart';
import '../../../domain/entities/postgres_config.dart';
import '../../../domain/services/i_sql_server_backup_service.dart';
import '../../../domain/services/i_sybase_backup_service.dart';
import '../../../domain/services/i_postgres_backup_service.dart';
import '../common/common.dart';

enum DatabaseType { sqlServer, sybase, postgresql }

class SqlServerConfigDialog extends StatefulWidget {
  final SqlServerConfig? config;
  final DatabaseType initialType;

  const SqlServerConfigDialog({
    super.key,
    this.config,
    this.initialType = DatabaseType.sqlServer,
  });

  /// Retorna SqlServerConfig ou SybaseConfig dependendo do tipo selecionado
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
  final _serverController = TextEditingController(); // Para SQL Server e Sybase
  final _hostController = TextEditingController(); // Para PostgreSQL
  final _databaseController = TextEditingController();
  final _databaseNameController =
      TextEditingController(); // Para Sybase: Nome do Banco de Dados
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '1433');

  DatabaseType _selectedType = DatabaseType.sqlServer;
  bool _isEnabled = true;
  bool _isTestingConnection = false;
  bool _isLoadingDatabases = false;
  List<String> _databases = [];
  String? _selectedDatabase;

  late final ISqlServerBackupService _backupService;
  late final ISybaseBackupService _sybaseBackupService;
  late final IPostgresBackupService _postgresBackupService;

  bool get isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    _backupService = getIt<ISqlServerBackupService>();
    _sybaseBackupService = getIt<ISybaseBackupService>();
    _postgresBackupService = getIt<IPostgresBackupService>();

    // Priorizar initialType se fornecido, caso contrário detectar baseado no config
    if (widget.initialType != DatabaseType.sqlServer) {
      // Se initialType foi fornecido explicitamente, usar ele
      _selectedType = widget.initialType;
    } else if (widget.config != null) {
      // Detectar tipo de banco quando está editando (apenas se initialType não foi fornecido)
      // Se porta é 2638 (padrão Sybase) ou database termina com .db (arquivo Sybase)
      // assume que é Sybase
      if (widget.config!.port == 2638 ||
          widget.config!.database.toLowerCase().endsWith('.db')) {
        _selectedType = DatabaseType.sybase;
      } else {
        _selectedType = DatabaseType.sqlServer;
      }
    } else {
      _selectedType = widget.initialType;
    }

    // Carregar dados do config se estiver editando
    if (widget.config != null) {
      _nameController.text = widget.config!.name;
      
      // Para PostgreSQL, usar server como host (já que foi convertido temporariamente)
      if (_selectedType == DatabaseType.postgresql) {
        _hostController.text = widget.config!.server;
      } else {
        _serverController.text = widget.config!.server;
      }
      
      _databaseController.text = widget.config!.database;
      _usernameController.text = widget.config!.username;
      _passwordController.text = widget.config!.password;
      _portController.text = widget.config!.port.toString();
      _isEnabled = widget.config!.enabled;
      _selectedDatabase = widget.config!.database;

      // Se for Sybase, tentar extrair databaseName do database
      // (assumindo que pode estar salvo como databaseName ou serverName)
      if (_selectedType == DatabaseType.sybase) {
        // Se o config for SybaseConfig, usar databaseName
        // Caso contrário, usar o database como fallback
        _databaseNameController.text = widget.config!.database;
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

        // Ajustar porta padrão
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
                  ? 'Editar Configuração'
                  : 'Nova Configuração de Banco de Dados',
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
                // ComboBox tipo de banco de dados
                AppDropdown<DatabaseType>(
                  label: 'Tipo de Banco de Dados',
                  value: _selectedType,
                  placeholder: const Text('Tipo de Banco de Dados'),
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

                // Nome da configuração
                AppTextField(
                  controller: _nameController,
                  label: 'Nome da Configuração',
                  hint: _selectedType == DatabaseType.sqlServer
                      ? 'Ex: Produção SQL Server'
                      : _selectedType == DatabaseType.postgresql
                      ? 'Ex: Produção PostgreSQL'
                      : 'Ex: Produção Sybase',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nome é obrigatório';
                    }
                    return null;
                  },
                  prefixIcon: const Icon(FluentIcons.tag),
                ),
                const SizedBox(height: 16),

                // Campos específicos por tipo
                if (_selectedType == DatabaseType.sqlServer)
                  _buildSqlServerFields(context)
                else if (_selectedType == DatabaseType.sybase)
                  _buildSybaseFields(context)
                else if (_selectedType == DatabaseType.postgresql)
                  _buildPostgresFields(context),

                const SizedBox(height: 16),

                // Usuário
                AppTextField(
                  controller: _usernameController,
                  label: 'Usuário',
                  hint: _selectedType == DatabaseType.sqlServer
                      ? 'sa ou usuário do SQL Server'
                      : _selectedType == DatabaseType.postgresql
                          ? 'postgres ou usuário do PostgreSQL'
                          : 'DBA ou usuário do Sybase',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Usuário é obrigatório';
                    }
                    return null;
                  },
                  prefixIcon: const Icon(FluentIcons.contact),
                ),
                const SizedBox(height: 16),

                // Senha
                PasswordField(
                  controller: _passwordController,
                  hint: 'Senha do usuário',
                ),
                const SizedBox(height: 24),

                // Switch habilitado
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
                  'Configuração ativa para uso em agendamentos',
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

  Widget _buildSqlServerFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Servidor e Porta
        Row(
          children: [
            Expanded(
              flex: 3,
              child: AppTextField(
                controller: _serverController,
                label: 'Servidor',
                hint: 'localhost ou IP\\INSTANCIA',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Servidor é obrigatório';
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
                hint: '1433',
                prefixIcon: FluentIcons.number_field,
                minValue: 1,
                maxValue: 65535,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Banco de dados
        _databases.isEmpty && !_isLoadingDatabases
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: _databaseController,
                    label: 'Nome do Banco de Dados',
                    hint: 'Digite ou clique em "Testar Conexão" para carregar',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Nome do banco é obrigatório';
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
                            'Preencha servidor, porta, usuário e senha, depois clique em "Testar Conexão" para carregar os bancos no dropdown',
                            style: FluentTheme.of(context).typography.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      label: 'Banco de Dados',
                      value: _selectedDatabase,
                      placeholder: Text(
                        _isLoadingDatabases
                            ? 'Carregando bancos...'
                            : _databases.isEmpty
                            ? 'Nenhum banco encontrado'
                            : 'Selecione o banco',
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
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: const SizedBox(
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
        // Nome do Servidor (Engine Name) e Porta
        Row(
          children: [
            Expanded(
              flex: 3,
              child: AppTextField(
                controller: _serverController,
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

        // Nome do Banco de Dados
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
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(FluentIcons.info, size: 18, color: AppColors.primary),
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
      ],
    );
  }

  Widget _buildPostgresFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Host e Porta
        Row(
          children: [
            Expanded(
              flex: 3,
              child: AppTextField(
                controller: _hostController,
                label: 'Host',
                hint: 'localhost ou IP',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Host é obrigatório';
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
                hint: '5432',
                prefixIcon: FluentIcons.number_field,
                minValue: 1,
                maxValue: 65535,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Banco de dados
        _databases.isEmpty && !_isLoadingDatabases
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: _databaseController,
                    label: 'Nome do Banco de Dados',
                    hint:
                        'Digite ou clique em \'Testar Conexão\' para carregar',
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
                            'Preencha host, porta, usuário e senha, depois clique em \'Testar Conexão\' para carregar os bancos no dropdown',
                            style: FluentTheme.of(context).typography.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : _isLoadingDatabases
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
                    label: 'Nome do Banco de Dados',
                    value: _selectedDatabase,
                    placeholder: const Text('Selecione um banco de dados'),
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
                    label: 'Nome do Banco de Dados (Manual)',
                    hint: 'Digite o nome do banco de dados',
                    validator: (value) {
                      if ((_selectedDatabase == null ||
                              _selectedDatabase!.isEmpty) &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Selecione ou digite um nome de banco de dados';
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
    // Validações específicas por tipo
    if (_selectedType == DatabaseType.sybase) {
      // Validações para Sybase
      if (_serverController.text.trim().isEmpty ||
          _portController.text.trim().isEmpty ||
          _databaseNameController.text.trim().isEmpty ||
          _usernameController.text.trim().isEmpty ||
          _passwordController.text.isEmpty) {
        MessageModal.showWarning(
          context,
          message:
              'Preencha nome da máquina, porta, nome do banco de dados, usuário e senha para testar',
        );
        return;
      }

      setState(() {
        _isTestingConnection = true;
      });

      try {
        final port = int.tryParse(_portController.text.trim());
        if (port == null || port < 1 || port > 65535) {
          throw Exception('Porta inválida. Deve estar entre 1 e 65535.');
        }

        final testConfig = SybaseConfig(
          name: 'temp',
          serverName: _serverController.text.trim(),
          databaseName: _databaseNameController.text.trim(),
          databaseFile: '', // Não necessário para backup
          port: port,
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
      return;
    }

    // Validações para PostgreSQL
    if (_selectedType == DatabaseType.postgresql) {
      if (_hostController.text.trim().isEmpty ||
          _portController.text.trim().isEmpty ||
          _usernameController.text.trim().isEmpty ||
          _passwordController.text.isEmpty) {
        MessageModal.showWarning(
          context,
          message: 'Preencha host, porta, usuário e senha para testar',
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
          throw Exception('Porta inválida. Deve estar entre 1 e 65535.');
        }

        final tempConfig = PostgresConfig(
          name: 'temp',
          host: _hostController.text.trim(),
          port: port,
          database: 'postgres',
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );

        final connectionResult = await _postgresBackupService.testConnection(
          tempConfig,
        );

        await connectionResult.fold(
          (success) async {
            // Conexão bem-sucedida, agora listar bancos
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
                        ? 'Conexão OK, mas nenhum banco encontrado'
                        : 'Conexão OK! ${databases.length} banco(s) encontrado(s). Selecione um no dropdown.',
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
                    message: 'Conexão OK, mas erro ao listar bancos: $message',
                  );
                }
              },
            );
          },
          (failure) async {
            // Falha na conexão
            if (mounted) {
              setState(() {
                _isLoadingDatabases = false;
                _isTestingConnection = false;
              });
              String message = failure is Failure
                  ? failure.message
                  : failure.toString();
              
              // Se a mensagem contém erro de psql não encontrado, garantir mensagem melhorada
              final messageLower = message.toLowerCase();
              if ((messageLower.contains('psql') ||
                      messageLower.contains("'psql'")) &&
                  (messageLower.contains('não é reconhecido') ||
                      messageLower.contains("não reconhecido") ||
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
                    'Consulte: docs\\path_setup.md para mais detalhes.';
              }
              
              MessageModal.showError(
                context,
                title: 'Erro ao Testar Conexão',
                message: message,
              );
            }
          },
        );
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingDatabases = false;
            _isTestingConnection = false;
          });
          MessageModal.showError(context, title: 'Erro', message: e.toString());
        }
      }
      return;
    }

    // Validações para SQL Server
    if (_serverController.text.trim().isEmpty ||
        _portController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      MessageModal.showWarning(
        context,
        message: 'Preencha servidor, porta, usuário e senha para testar',
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
        throw Exception('Porta inválida');
      }

      final tempConfig = SqlServerConfig(
        name: 'temp',
        server: _serverController.text.trim(),
        port: port,
        database: 'master',
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      final connectionResult = await _backupService.testConnection(tempConfig);

      await connectionResult.fold(
        (success) async {
          if (!success) {
            throw Exception('Conexão falhou');
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
                      ? 'Conexão OK, mas nenhum banco encontrado'
                      : 'Conexão OK! ${databases.length} banco(s) encontrado(s). Selecione um no dropdown.',
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
                  message: 'Conexão OK, mas erro ao listar bancos: $message',
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
              title: 'Erro ao Testar Conexão',
              message: message,
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDatabases = false;
          _isTestingConnection = false;
        });
        MessageModal.showError(context, title: 'Erro', message: e.toString());
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
        message: 'Selecione ou informe um banco de dados',
      );
      return;
    }

    if (_selectedType == DatabaseType.sybase &&
        _databaseNameController.text.trim().isEmpty) {
      MessageModal.showError(
        context,
        message: 'Informe o nome do banco de dados',
      );
      return;
    }

    if (_selectedType == DatabaseType.postgresql) {
      final database = _selectedDatabase ?? _databaseController.text.trim();
      if (database.isEmpty) {
        MessageModal.showError(
          context,
          message: 'Selecione ou informe um banco de dados',
        );
        return;
      }

      final postgresConfig = PostgresConfig(
        id: widget.config?.id,
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: port,
        database: database,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        enabled: _isEnabled,
        createdAt: widget.config?.createdAt,
        updatedAt: widget.config?.updatedAt,
      );
      Navigator.of(context).pop(postgresConfig);
      return;
    }

    // Retornar o tipo correto baseado na seleção
    if (_selectedType == DatabaseType.sybase) {
      final sybaseConfig = SybaseConfig(
        id: widget.config?.id,
        name: _nameController.text.trim(),
        serverName: _serverController.text.trim(),
        databaseName: _databaseNameController.text.trim(),
        databaseFile: '', // Não necessário para backup
        port: port,
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
        database: database,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        port: port,
        enabled: _isEnabled,
        createdAt: widget.config?.createdAt,
        updatedAt: widget.config?.updatedAt,
      );
      Navigator.of(context).pop(sqlServerConfig);
    }
  }
}
