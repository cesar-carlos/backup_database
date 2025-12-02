import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/providers/google_auth_provider.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/errors/failure.dart';
import '../../../domain/entities/backup_destination.dart';
import '../../../infrastructure/external/destinations/ftp_destination_service.dart'
    as ftp;
import '../common/common.dart';

class DestinationDialog extends StatefulWidget {
  final BackupDestination? destination;

  const DestinationDialog({
    super.key,
    this.destination,
  });

  static Future<BackupDestination?> show(
    BuildContext context, {
    BackupDestination? destination,
  }) {
    return showDialog<BackupDestination>(
      context: context,
      builder: (context) => DestinationDialog(destination: destination),
    );
  }

  @override
  State<DestinationDialog> createState() => _DestinationDialogState();
}

class _DestinationDialogState extends State<DestinationDialog> {
  final _formKey = GlobalKey<FormState>();
  
  late DestinationType _selectedType;
  final _nameController = TextEditingController();
  
  // Local
  final _localPathController = TextEditingController();
  bool _createSubfoldersByDate = true;
  
  // FTP
  final _ftpHostController = TextEditingController();
  final _ftpPortController = TextEditingController(text: '21');
  final _ftpUsernameController = TextEditingController();
  final _ftpPasswordController = TextEditingController();
  final _ftpRemotePathController = TextEditingController(text: '/backups');
  bool _useFtps = false;
  bool _obscureFtpPassword = true;
  
  // Google Drive
  final _googleFolderNameController = TextEditingController(text: 'Backups');
  
  // Common
  final _retentionDaysController = TextEditingController(text: '30');
  bool _isEnabled = true;
  bool _isTestingFtpConnection = false;

  bool get isEditing => widget.destination != null;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.destination?.type ?? DestinationType.local;
    
    if (widget.destination != null) {
      _nameController.text = widget.destination!.name;
      _isEnabled = widget.destination!.enabled;
      
      final config = jsonDecode(widget.destination!.config) as Map<String, dynamic>;
      
      switch (widget.destination!.type) {
        case DestinationType.local:
          _localPathController.text = config['path'] ?? '';
          _createSubfoldersByDate = config['createSubfoldersByDate'] ?? true;
          _retentionDaysController.text = (config['retentionDays'] ?? 30).toString();
          break;
        case DestinationType.ftp:
          _ftpHostController.text = config['host'] ?? '';
          _ftpPortController.text = (config['port'] ?? 21).toString();
          _ftpUsernameController.text = config['username'] ?? '';
          _ftpPasswordController.text = config['password'] ?? '';
          _ftpRemotePathController.text = config['remotePath'] ?? '/backups';
          _useFtps = config['useFtps'] ?? false;
          _retentionDaysController.text = (config['retentionDays'] ?? 30).toString();
          break;
        case DestinationType.googleDrive:
          _googleFolderNameController.text = config['folderName'] ?? 'Backups';
          _retentionDaysController.text = (config['retentionDays'] ?? 30).toString();
          break;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _localPathController.dispose();
    _ftpHostController.dispose();
    _ftpPortController.dispose();
    _ftpUsernameController.dispose();
    _ftpPasswordController.dispose();
    _ftpRemotePathController.dispose();
    _googleFolderNameController.dispose();
    _retentionDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
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
                      // Tipo de destino
                      DropdownButtonFormField<DestinationType>(
                        initialValue: _selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de Destino',
                          border: OutlineInputBorder(),
                        ),
                        items: DestinationType.values.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Row(
                              children: [
                                Icon(_getTypeIcon(type), size: 20),
                                const SizedBox(width: 8),
                                Text(_getTypeName(type)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: isEditing ? null : (value) {
                          setState(() {
                            _selectedType = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Nome
                      AppTextField(
                        controller: _nameController,
                        label: 'Nome do Destino',
                        hint: 'Ex: Backup Local, FTP Servidor',
                        prefixIcon: const Icon(Icons.label_outline),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nome é obrigatório';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Campos específicos por tipo
                      if (_selectedType == DestinationType.local)
                        _buildLocalFields()
                      else if (_selectedType == DestinationType.ftp)
                        _buildFtpFields()
                      else
                        _buildGoogleDriveFields(),
                      
                      const SizedBox(height: 16),
                      
                      // Retenção
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppTextField(
                            controller: _retentionDaysController,
                            label: 'Dias de Retenção',
                            hint: 'Ex: 30 (mantém backups por 30 dias)',
                            prefixIcon: const Icon(Icons.delete_outline),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Dias de retenção é obrigatório';
                              }
                              final days = int.tryParse(value);
                              if (days == null || days < 1) {
                                return 'Informe um valor válido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: _retentionDaysController,
                                    builder: (context, value, child) {
                                      final days = int.tryParse(value.text) ?? 30;
                                      final cutoffDate = DateTime.now().subtract(Duration(days: days));
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Limpeza Automática',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Backups anteriores a ${_formatDate(cutoffDate)} serão excluídos automaticamente após cada backup executado.',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Habilitado
                      SwitchListTile(
                        title: const Text('Habilitado'),
                        subtitle: const Text('Destino ativo para uso em agendamentos'),
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

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getTypeIcon(_selectedType),
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Text(
            isEditing ? 'Editar Destino' : 'Novo Destino',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const Spacer(),
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
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(isEditing ? 'Salvar' : 'Criar'),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _localPathController,
                label: 'Caminho da Pasta',
                hint: 'C:\\Backups',
                prefixIcon: const Icon(Icons.folder_outlined),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Caminho é obrigatório';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Selecionar pasta',
              onPressed: _selectLocalFolder,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Criar subpastas por data'),
          subtitle: const Text('Organiza backups em pastas YYYY-MM-DD'),
          value: _createSubfoldersByDate,
          onChanged: (value) {
            setState(() {
              _createSubfoldersByDate = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildFtpFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: AppTextField(
                controller: _ftpHostController,
                label: 'Servidor FTP',
                hint: 'ftp.exemplo.com',
                prefixIcon: const Icon(Icons.dns_outlined),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Servidor é obrigatório';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: AppTextField(
                controller: _ftpPortController,
                label: 'Porta',
                hint: '21',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Porta é obrigatória';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _ftpUsernameController,
          label: 'Usuário',
          hint: 'usuario_ftp',
          prefixIcon: const Icon(Icons.person_outline),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Usuário é obrigatório';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _ftpPasswordController,
          label: 'Senha',
          hint: 'Senha do FTP',
          obscureText: _obscureFtpPassword,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(
              _obscureFtpPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            ),
            onPressed: () {
              setState(() {
                _obscureFtpPassword = !_obscureFtpPassword;
              });
            },
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Senha é obrigatória';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _ftpRemotePathController,
          label: 'Caminho Remoto',
          hint: '/backups',
          prefixIcon: const Icon(Icons.folder_outlined),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Caminho remoto é obrigatório';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Usar FTPS'),
          subtitle: const Text('Conexão FTP segura (SSL/TLS)'),
          value: _useFtps,
          onChanged: (value) {
            setState(() {
              _useFtps = value;
            });
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _isTestingFtpConnection ? null : _testFtpConnection,
          icon: _isTestingFtpConnection
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check),
          label: const Text('Testar Conexão FTP'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleDriveFields() {
    final googleAuth = getIt<GoogleAuthProvider>();
    
    return ListenableBuilder(
      listenable: googleAuth,
      builder: (context, _) {
        return Column(
          children: [
            // Status de Autenticação
            _buildGoogleAuthStatus(googleAuth),
            const SizedBox(height: 16),
            
            // Configuração OAuth (se não configurado)
            if (!googleAuth.isConfigured) ...[
              _buildOAuthConfigSection(googleAuth),
              const SizedBox(height: 16),
            ],
            
            // Nome da pasta
            AppTextField(
              controller: _googleFolderNameController,
              label: 'Nome da Pasta no Google Drive',
              hint: 'Backups',
              prefixIcon: const Icon(Icons.cloud_outlined),
              enabled: googleAuth.isSignedIn,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Nome da pasta é obrigatório';
                }
                return null;
              },
            ),
            
            if (!googleAuth.isSignedIn) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Conecte-se ao Google para configurar o destino.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
  
  Widget _buildGoogleAuthStatus(GoogleAuthProvider googleAuth) {
    final isSignedIn = googleAuth.isSignedIn;
    final isLoading = googleAuth.isLoading;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSignedIn 
            ? Colors.green.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSignedIn 
              ? Colors.green.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSignedIn ? Icons.check_circle : Icons.cloud_off_outlined,
                color: isSignedIn ? Colors.green : Theme.of(context).colorScheme.outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSignedIn 
                      ? 'Conectado como ${googleAuth.currentEmail}'
                      : 'Não conectado ao Google',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isSignedIn)
                OutlinedButton.icon(
                  onPressed: isLoading ? null : () => googleAuth.signOut(),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Desconectar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                )
              else if (googleAuth.isConfigured)
                ElevatedButton.icon(
                  onPressed: isLoading ? null : () => _connectToGoogle(googleAuth),
                  icon: isLoading 
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login, size: 18),
                  label: Text(isLoading ? 'Conectando...' : 'Conectar ao Google'),
                ),
            ],
          ),
          if (googleAuth.error != null) ...[
            const SizedBox(height: 8),
            Text(
              googleAuth.error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildOAuthConfigSection(GoogleAuthProvider googleAuth) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.settings_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Configuração OAuth',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Para usar o Google Drive, configure as credenciais OAuth do Google Cloud Console.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showOAuthConfigDialog(googleAuth),
            icon: const Icon(Icons.key, size: 18),
            label: const Text('Configurar Credenciais'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _connectToGoogle(GoogleAuthProvider googleAuth) async {
    final success = await googleAuth.signIn();
    if (success && mounted) {
      _showSuccess('Conectado ao Google com sucesso!');
    }
  }
  
  Future<void> _showOAuthConfigDialog(GoogleAuthProvider googleAuth) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _OAuthConfigDialog(
        googleAuth: googleAuth,
        initialClientId: googleAuth.oauthConfig?.clientId ?? '',
        initialClientSecret: googleAuth.oauthConfig?.clientSecret ?? '',
      ),
    );
    
    if (result == true && mounted) {
      _showSuccess('Credenciais OAuth configuradas!');
    }
  }

  IconData _getTypeIcon(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return Icons.folder_outlined;
      case DestinationType.ftp:
        return Icons.cloud_upload_outlined;
      case DestinationType.googleDrive:
        return Icons.add_to_drive_outlined;
    }
  }

  String _getTypeName(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return 'Pasta Local';
      case DestinationType.ftp:
        return 'Servidor FTP';
      case DestinationType.googleDrive:
        return 'Google Drive';
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    return '$day/$month/$year';
  }

  Future<void> _selectLocalFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecionar pasta de destino',
    );
    if (result != null) {
      setState(() {
        _localPathController.text = result;
      });
    }
  }

  Future<void> _testFtpConnection() async {
    // Validar campos obrigatórios
    if (_ftpHostController.text.trim().isEmpty) {
      _showError('Servidor FTP é obrigatório');
      return;
    }
    if (_ftpPortController.text.trim().isEmpty) {
      _showError('Porta é obrigatória');
      return;
    }
    if (_ftpUsernameController.text.trim().isEmpty) {
      _showError('Usuário é obrigatório');
      return;
    }
    if (_ftpPasswordController.text.trim().isEmpty) {
      _showError('Senha é obrigatória');
      return;
    }

    setState(() {
      _isTestingFtpConnection = true;
    });

    try {
      final port = int.tryParse(_ftpPortController.text.trim());
      if (port == null || port < 1 || port > 65535) {
        _showError('Porta inválida. Use um valor entre 1 e 65535');
        return;
      }

      final config = ftp.FtpDestinationConfig(
        host: _ftpHostController.text.trim(),
        port: port,
        username: _ftpUsernameController.text.trim(),
        password: _ftpPasswordController.text,
        remotePath: _ftpRemotePathController.text.trim(),
        useFtps: _useFtps,
      );

      final ftpService = getIt<ftp.FtpDestinationService>();
      final result = await ftpService.testConnection(config);

      result.fold(
        (success) {
          if (success) {
            _showSuccess('Conexão FTP estabelecida com sucesso!');
          } else {
            _showError('Falha ao conectar ao servidor FTP');
          }
        },
        (failure) {
          final message = failure is Failure ? failure.message : failure.toString();
          _showError('Erro ao testar conexão FTP:\n$message');
        },
      );
    } catch (e) {
      _showError('Erro inesperado: $e');
    } finally {
      setState(() {
        _isTestingFtpConnection = false;
      });
    }
  }

  void _showSuccess(String message) {
    MessageModal.showSuccess(
      context,
      message: message,
    );
  }

  void _showError(String message) {
    ErrorModal.show(
      context,
      message: message,
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validar conexão Google Drive
    if (_selectedType == DestinationType.googleDrive) {
      final googleAuth = getIt<GoogleAuthProvider>();
      if (!googleAuth.isSignedIn) {
        _showError('Conecte-se ao Google antes de salvar.');
        return;
      }
    }

    final retentionDays = int.parse(_retentionDaysController.text);
    String configJson;

    switch (_selectedType) {
      case DestinationType.local:
        configJson = jsonEncode({
          'path': _localPathController.text.trim(),
          'createSubfoldersByDate': _createSubfoldersByDate,
          'retentionDays': retentionDays,
        });
        break;
      case DestinationType.ftp:
        configJson = jsonEncode({
          'host': _ftpHostController.text.trim(),
          'port': int.parse(_ftpPortController.text),
          'username': _ftpUsernameController.text.trim(),
          'password': _ftpPasswordController.text,
          'remotePath': _ftpRemotePathController.text.trim(),
          'useFtps': _useFtps,
          'retentionDays': retentionDays,
        });
        break;
      case DestinationType.googleDrive:
        configJson = jsonEncode({
          'folderName': _googleFolderNameController.text.trim(),
          'folderId': 'root',
          'retentionDays': retentionDays,
        });
        break;
    }

    final destination = BackupDestination(
      id: widget.destination?.id,
      name: _nameController.text.trim(),
      type: _selectedType,
      config: configJson,
      enabled: _isEnabled,
      createdAt: widget.destination?.createdAt,
    );

    Navigator.of(context).pop(destination);
  }
}

class _OAuthConfigDialog extends StatefulWidget {
  final GoogleAuthProvider googleAuth;
  final String initialClientId;
  final String initialClientSecret;

  const _OAuthConfigDialog({
    required this.googleAuth,
    required this.initialClientId,
    required this.initialClientSecret,
  });

  @override
  State<_OAuthConfigDialog> createState() => _OAuthConfigDialogState();
}

class _OAuthConfigDialogState extends State<_OAuthConfigDialog> {
  late final TextEditingController _clientIdController;
  late final TextEditingController _clientSecretController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController(text: widget.initialClientId);
    _clientSecretController = TextEditingController(text: widget.initialClientSecret);
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_clientIdController.text.trim().isEmpty) {
      ErrorModal.show(
        context,
        message: 'Client ID é obrigatório',
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await widget.googleAuth.configureOAuth(
      clientId: _clientIdController.text.trim(),
      clientSecret: _clientSecretController.text.trim().isEmpty
          ? null
          : _clientSecretController.text.trim(),
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.cloud_outlined),
          SizedBox(width: 8),
          Text('Configurar Google OAuth'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Obtenha as credenciais no Google Cloud Console:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1. Acesse console.cloud.google.com',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text('2. Crie um projeto ou selecione existente',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text('3. Ative a Google Drive API',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text('4. Crie credenciais OAuth (Desktop)',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('5. Na credencial criada, adicione em "URIs de redirecionamento autorizados":',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      'http://localhost:8085/oauth2redirect',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nota: localhost é o seu próprio computador. O app cria um servidor temporário automaticamente durante a autenticação.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _clientIdController,
              decoration: const InputDecoration(
                labelText: 'Client ID *',
                hintText: 'xxx.apps.googleusercontent.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientSecretController,
              decoration: const InputDecoration(
                labelText: 'Client Secret (opcional)',
                hintText: 'GOCSPX-xxx',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              enabled: !_isLoading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

