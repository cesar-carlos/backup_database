import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/sql_server_config.dart';
import '../../../domain/entities/sybase_config.dart';
import '../../../infrastructure/external/process/sql_server_backup_service.dart';
import '../../../infrastructure/external/process/sybase_backup_service.dart';
import '../common/common.dart';

enum DatabaseType { sqlServer, sybase }

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
  final _serverController = TextEditingController();
  final _databaseController = TextEditingController();
  final _databaseNameController = TextEditingController(); // Para Sybase: Nome do Banco de Dados
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '1433');

  DatabaseType _selectedType = DatabaseType.sqlServer;
  bool _isEnabled = true;
  bool _obscurePassword = true;
  bool _isTestingConnection = false;
  bool _isLoadingDatabases = false;
  List<String> _databases = [];
  String? _selectedDatabase;

  late final SqlServerBackupService _backupService;
  late final SybaseBackupService _sybaseBackupService;

  bool get isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    _backupService = getIt<SqlServerBackupService>();
    _sybaseBackupService = getIt<SybaseBackupService>();

    // Detectar tipo de banco quando está editando
    if (widget.config != null) {
      // Se porta é 2638 (padrão Sybase) ou database termina com .db (arquivo Sybase)
      // assume que é Sybase
      if (widget.config!.port == 2638 ||
          widget.config!.database.toLowerCase().endsWith('.db')) {
        _selectedType = DatabaseType.sybase;
      } else {
        _selectedType = DatabaseType.sqlServer;
      }

      _nameController.text = widget.config!.name;
      _serverController.text = widget.config!.server;
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
    } else {
      _selectedType = widget.initialType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
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

        // Ajustar porta padrão
        if (type == DatabaseType.sqlServer) {
          _portController.text = '1433';
        } else {
          _portController.text = '2638';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Dropdown tipo de banco de dados
                      DropdownButtonFormField<DatabaseType>(
                        initialValue: _selectedType,
                        decoration: InputDecoration(
                          labelText: 'Tipo de Banco de Dados',
                          border: const OutlineInputBorder(),
                          prefixIcon: Icon(
                            _selectedType == DatabaseType.sqlServer
                                ? Icons.storage_outlined
                                : Icons.dns_outlined,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: DatabaseType.sqlServer,
                            child: Text('SQL Server'),
                          ),
                          DropdownMenuItem(
                            value: DatabaseType.sybase,
                            child: Text('Sybase SQL Anywhere'),
                          ),
                        ],
                        onChanged: isEditing ? null : _onTypeChanged,
                      ),
                      const SizedBox(height: 16),

                      // Nome da configuração
                      AppTextField(
                        controller: _nameController,
                        label: 'Nome da Configuração',
                        hint: _selectedType == DatabaseType.sqlServer
                            ? 'Ex: Produção SQL Server'
                            : 'Ex: Produção Sybase',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nome é obrigatório';
                          }
                          return null;
                        },
                        prefixIcon: const Icon(Icons.label_outline),
                      ),
                      const SizedBox(height: 16),

                      // Campos específicos por tipo
                      if (_selectedType == DatabaseType.sqlServer)
                        _buildSqlServerFields(context)
                      else
                        _buildSybaseFields(context),

                      const SizedBox(height: 16),

                      // Usuário
                      AppTextField(
                        controller: _usernameController,
                        label: 'Usuário',
                        hint: _selectedType == DatabaseType.sqlServer
                            ? 'sa ou usuário do SQL Server'
                            : 'DBA ou usuário do Sybase',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Usuário é obrigatório';
                          }
                          return null;
                        },
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      const SizedBox(height: 16),

                      // Senha
                      AppTextField(
                        controller: _passwordController,
                        label: 'Senha',
                        hint: 'Senha do usuário',
                        obscureText: _obscurePassword,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Senha é obrigatória';
                          }
                          return null;
                        },
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Switch habilitado
                      SwitchListTile(
                        title: const Text('Habilitado'),
                        subtitle: const Text(
                          'Configuração ativa para uso em agendamentos',
                        ),
                        value: _isEnabled,
                        onChanged: (value) {
                          setState(() {
                            _isEnabled = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
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
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: AppTextField(
                controller: _portController,
                label: 'Porta',
                hint: '1433',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Porta é obrigatória';
                  }
                  final port = int.tryParse(value);
                  if (port == null || port < 1 || port > 65535) {
                    return 'Porta inválida';
                  }
                  return null;
                },
                prefixIcon: const Icon(Icons.numbers_outlined),
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
                    prefixIcon: const Icon(Icons.storage_outlined),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Preencha servidor, porta, usuário e senha, depois clique em "Testar Conexão" para carregar os bancos no dropdown',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : DropdownButtonFormField<String>(
                initialValue: _selectedDatabase,
                decoration: InputDecoration(
                  labelText: 'Banco de Dados',
                  hintText: _isLoadingDatabases
                      ? 'Carregando bancos...'
                      : _databases.isEmpty
                      ? 'Nenhum banco encontrado'
                      : 'Selecione o banco',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.storage_outlined),
                  suffixIcon: _isLoadingDatabases
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _databases.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Recarregar bancos',
                          onPressed: _testConnection,
                        )
                      : null,
                ),
                items: _databases.map((db) {
                  return DropdownMenuItem<String>(value: db, child: Text(db));
                }).toList(),
                onChanged: _isLoadingDatabases || _databases.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          _selectedDatabase = value;
                          _databaseController.text = value ?? '';
                        });
                      },
                validator: (value) {
                  if (_databases.isNotEmpty &&
                      (value == null || value.trim().isEmpty)) {
                    return 'Selecione um banco de dados';
                  }
                  if (_databases.isEmpty &&
                      (_databaseController.text.trim().isEmpty)) {
                    return 'Nome do banco é obrigatório';
                  }
                  return null;
                },
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
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: AppTextField(
                controller: _portController,
                label: 'Porta',
                hint: '2638',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Porta é obrigatória';
                  }
                  final port = int.tryParse(value);
                  if (port == null || port < 1 || port > 65535) {
                    return 'Porta inválida';
                  }
                  return null;
                },
                prefixIcon: const Icon(Icons.numbers_outlined),
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
          prefixIcon: const Icon(Icons.storage_outlined),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O Engine Name e DBN geralmente são iguais ao nome do serviço Sybase (ex: VL)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _selectedType == DatabaseType.sqlServer
                ? Icons.storage_outlined
                : Icons.dns_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing
                  ? 'Editar Configuração'
                  : 'Nova Configuração de Banco de Dados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _isTestingConnection ? null : _testConnection,
            icon: _isTestingConnection
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('Testar Conexão'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(isEditing ? 'Salvar' : 'Criar'),
          ),
        ],
      ),
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
          message: 'Preencha nome da máquina, porta, nome do banco de dados, usuário e senha para testar',
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

            ErrorModal.show(
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

        ErrorModal.show(
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
            server: _serverController.text.trim(),
            port: port,
            username: _usernameController.text.trim(),
            password: _passwordController.text,
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
            ErrorModal.show(
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
        ErrorModal.show(
          context,
          title: 'Erro',
          message: e.toString(),
        );
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
      ErrorModal.show(
        context,
        message: 'Selecione ou informe um banco de dados',
      );
      return;
    }

    if (_selectedType == DatabaseType.sybase &&
        _databaseNameController.text.trim().isEmpty) {
      ErrorModal.show(
        context,
        message: 'Informe o nome do banco de dados',
      );
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
