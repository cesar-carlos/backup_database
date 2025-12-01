import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/sybase_config.dart';
import '../../../infrastructure/external/process/sybase_backup_service.dart';
import '../common/common.dart';

class SybaseConfigDialog extends StatefulWidget {
  final SybaseConfig? config;

  const SybaseConfigDialog({
    super.key,
    this.config,
  });

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
  final _serverNameController = TextEditingController(); // Nome da máquina
  final _databaseNameController = TextEditingController(); // Nome do banco de dados
  final _portController = TextEditingController(text: '2638');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isEnabled = true;
  bool _obscurePassword = true;
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
        databaseFile: '', // Não necessário para backup, mas mantido para compatibilidade
        port: port,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      final result = await _backupService.testConnection(testConfig);

      if (!mounted) return;

      result.fold(
        (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conexão testada com sucesso!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
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

      // Log do erro para debug
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
      databaseFile: '', // Não necessário para backup, mas mantido para compatibilidade
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
                        prefixIcon: const Icon(Icons.label_outline),
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
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
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
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _passwordController,
                        label: 'Senha',
                        obscureText: _obscurePassword,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
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
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('Habilitado'),
                              subtitle: const Text(
                                'Permitir uso desta configuração em agendamentos',
                              ),
                              value: _isEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _isEnabled = value;
                                });
                              },
                            ),
                          ),
                        ],
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
            Icons.dns_outlined,
            size: 28,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              isEditing ? 'Editar Configuração Sybase' : 'Nova Configuração Sybase',
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
}

