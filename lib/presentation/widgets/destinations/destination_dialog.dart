import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../application/providers/google_auth_provider.dart';
import '../../../application/providers/dropbox_auth_provider.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/errors/failure.dart';
import '../../../domain/entities/backup_destination.dart';
import '../../../infrastructure/external/destinations/ftp_destination_service.dart'
    as ftp;
import '../common/common.dart';

class DestinationDialog extends StatefulWidget {
  final BackupDestination? destination;

  const DestinationDialog({super.key, this.destination});

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

  // Google Drive
  final _googleFolderNameController = TextEditingController(text: 'Backups');

  // Dropbox
  final _dropboxFolderPathController = TextEditingController();
  final _dropboxFolderNameController = TextEditingController(text: 'Backups');

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

      final config =
          jsonDecode(widget.destination!.config) as Map<String, dynamic>;

      switch (widget.destination!.type) {
        case DestinationType.local:
          _localPathController.text = config['path'] ?? '';
          _createSubfoldersByDate = config['createSubfoldersByDate'] ?? true;
          _retentionDaysController.text = (config['retentionDays'] ?? 30)
              .toString();
          break;
        case DestinationType.ftp:
          _ftpHostController.text = config['host'] ?? '';
          _ftpPortController.text = (config['port'] ?? 21).toString();
          _ftpUsernameController.text = config['username'] ?? '';
          _ftpPasswordController.text = config['password'] ?? '';
          _ftpRemotePathController.text = config['remotePath'] ?? '/backups';
          _useFtps = config['useFtps'] ?? false;
          _retentionDaysController.text = (config['retentionDays'] ?? 30)
              .toString();
          break;
        case DestinationType.googleDrive:
          _googleFolderNameController.text = config['folderName'] ?? 'Backups';
          _retentionDaysController.text = (config['retentionDays'] ?? 30)
              .toString();
          break;
        case DestinationType.dropbox:
          _dropboxFolderPathController.text = config['folderPath'] ?? '';
          _dropboxFolderNameController.text = config['folderName'] ?? 'Backups';
          _retentionDaysController.text = (config['retentionDays'] ?? 30)
              .toString();
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
    _dropboxFolderPathController.dispose();
    _dropboxFolderNameController.dispose();
    _retentionDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: BoxConstraints(minWidth: 600, maxWidth: 600, maxHeight: 800),
      title: _buildTitle(),
      content: _buildContent(),
      actions: _buildActions(),
    );
  }

  Widget _buildTitle() {
    return Row(
      children: [
        Icon(_getTypeIcon(_selectedType), color: AppColors.primary),
        const SizedBox(width: 12),
        Text(
          isEditing ? 'Editar Destino' : 'Novo Destino',
          style: FluentTheme.of(context).typography.title,
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Container(
      constraints: const BoxConstraints(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTypeSelector(),
              const SizedBox(height: 16),
              _buildNameField(),
              const SizedBox(height: 16),
              _buildTypeSpecificFields(),
              const SizedBox(height: 16),
              _buildRetentionSection(),
              if (_selectedType == DestinationType.local) ...[
                const SizedBox(height: 16),
                _buildCreateSubfoldersSwitch(),
              ],
              if (_selectedType == DestinationType.ftp) ...[
                const SizedBox(height: 16),
                _buildFtpsSection(),
              ],
              const SizedBox(height: 16),
              _buildEnabledSwitch(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return AppDropdown<DestinationType>(
      label: 'Tipo de Destino',
      value: _selectedType,
      placeholder: const Text('Tipo de Destino'),
      items: DestinationType.values.map((type) {
        return ComboBoxItem<DestinationType>(
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
      onChanged: isEditing
          ? null
          : (value) {
              if (value != null) {
                setState(() {
                  _selectedType = value;
                });
              }
            },
    );
  }

  Widget _buildNameField() {
    return AppTextField(
      controller: _nameController,
      label: 'Nome do Destino',
      hint: 'Ex: Backup Local, FTP Servidor, Google Drive, Dropbox',
      prefixIcon: const Icon(FluentIcons.tag),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Nome é obrigatório';
        }
        return null;
      },
    );
  }

  Widget _buildTypeSpecificFields() {
    if (_selectedType == DestinationType.local) {
      return _buildLocalFields();
    } else if (_selectedType == DestinationType.ftp) {
      return _buildFtpFields();
    } else if (_selectedType == DestinationType.googleDrive) {
      return _buildGoogleDriveFields();
    } else {
      return _buildDropboxFields();
    }
  }

  Widget _buildRetentionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NumericField(
          controller: _retentionDaysController,
          label: 'Dias de Retenção',
          hint: 'Ex: 30 (mantém backups por 30 dias)',
          prefixIcon: FluentIcons.delete,
          minValue: 1,
        ),
        const SizedBox(height: 8),
        _buildRetentionInfo(),
      ],
    );
  }

  Widget _buildRetentionInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.info, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _retentionDaysController,
              builder: (context, value, child) {
                final days = int.tryParse(value.text) ?? 30;
                final cutoffDate = DateTime.now().subtract(
                  Duration(days: days),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Limpeza Automática',
                      style: FluentTheme.of(context).typography.caption
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Backups anteriores a ${_formatDate(cutoffDate)} serão excluídos automaticamente após cada backup executado.',
                      style: FluentTheme.of(context).typography.caption,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateSubfoldersSwitch() {
    return InfoLabel(
      label: 'Criar subpastas por data',
      child: ToggleSwitch(
        checked: _createSubfoldersByDate,
        onChanged: (value) {
          setState(() {
            _createSubfoldersByDate = value;
          });
        },
      ),
    );
  }

  Widget _buildFtpsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: 'Usar FTPS',
          child: ToggleSwitch(
            checked: _useFtps,
            onChanged: (value) {
              setState(() {
                _useFtps = value;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Conexão FTP segura (SSL/TLS)',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        ActionButton(
          label: 'Testar Conexão FTP',
          icon: FluentIcons.network_tower,
          onPressed: _testFtpConnection,
          isLoading: _isTestingFtpConnection,
        ),
      ],
    );
  }

  Widget _buildEnabledSwitch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          'Destino ativo para uso em agendamentos',
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    return [
      const CancelButton(),
      SaveButton(onPressed: _save, isEditing: isEditing),
    ];
  }

  Widget _buildLocalFields() {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: _localPathController,
                label: 'Caminho da Pasta',
                hint: 'C:\\Backups',
                prefixIcon: const Icon(FluentIcons.folder),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Caminho é obrigatório';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: IconButton(
                icon: const Icon(FluentIcons.folder_open),
                onPressed: _selectLocalFolder,
              ),
            ),
          ],
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
                prefixIcon: const Icon(FluentIcons.server),
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
              child: NumericField(
                controller: _ftpPortController,
                label: 'Porta',
                hint: '21',
                prefixIcon: FluentIcons.number_field,
                minValue: 1,
                maxValue: 65535,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _ftpUsernameController,
          label: 'Usuário',
          hint: 'usuario_ftp',
          prefixIcon: const Icon(FluentIcons.contact),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Usuário é obrigatório';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        PasswordField(
          controller: _ftpPasswordController,
          label: 'Senha FTP',
          hint: 'Senha do FTP',
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _ftpRemotePathController,
          label: 'Caminho Remoto',
          hint: '/backups',
          prefixIcon: const Icon(FluentIcons.folder),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Caminho remoto é obrigatório';
            }
            return null;
          },
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
            _buildGoogleAuthStatus(googleAuth),
            const SizedBox(height: 16),
            if (!googleAuth.isConfigured) ...[
              _buildOAuthConfigSection(googleAuth),
              const SizedBox(height: 16),
            ],
            _buildGoogleFolderField(googleAuth),
            if (!googleAuth.isSignedIn) ...[
              const SizedBox(height: 16),
              _buildGoogleNotSignedInWarning(),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGoogleFolderField(GoogleAuthProvider googleAuth) {
    return AppTextField(
      controller: _googleFolderNameController,
      label: 'Nome da Pasta no Google Drive',
      hint: 'Backups',
      prefixIcon: const Icon(FluentIcons.cloud),
      enabled: googleAuth.isSignedIn,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Nome da pasta é obrigatório';
        }
        return null;
      },
    );
  }

  Widget _buildGoogleNotSignedInWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorBackground.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.warning, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Conecte-se ao Google para configurar o destino.',
              style: FluentTheme.of(
                context,
              ).typography.caption?.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleAuthStatus(GoogleAuthProvider googleAuth) {
    final isSignedIn = googleAuth.isSignedIn;
    final isLoading = googleAuth.isLoading;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSignedIn
            ? AppColors.googleDriveSignedInBackground
            : FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSignedIn
              ? AppColors.googleDriveSignedInBorder
              : FluentTheme.of(
                  context,
                ).resources.controlStrokeColorDefault.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSignedIn
                    ? FluentIcons.check_mark
                    : FluentIcons.cloud_download,
                color: isSignedIn
                    ? AppColors.googleDriveSignedIn
                    : FluentTheme.of(
                        context,
                      ).resources.controlStrokeColorDefault,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSignedIn
                      ? 'Conectado como ${googleAuth.currentEmail ?? 'usuário'}'
                      : 'Não conectado ao Google',
                  style: FluentTheme.of(
                    context,
                  ).typography.body?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isSignedIn)
                Button(
                  onPressed: isLoading ? null : () => googleAuth.signOut(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.sign_out, size: 18),
                      const SizedBox(width: 8),
                      const Text('Desconectar'),
                    ],
                  ),
                )
              else if (googleAuth.isConfigured)
                Button(
                  onPressed: isLoading
                      ? null
                      : () => _connectToGoogle(googleAuth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      else
                        const Icon(FluentIcons.signin, size: 18),
                      const SizedBox(width: 8),
                      Text(isLoading ? 'Conectando...' : 'Conectar ao Google'),
                    ],
                  ),
                ),
            ],
          ),
          if (googleAuth.error != null) ...[
            const SizedBox(height: 8),
            Text(
              googleAuth.error!,
              style: FluentTheme.of(
                context,
              ).typography.caption?.copyWith(color: AppColors.error),
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
        color: FluentTheme.of(
          context,
        ).resources.cardBackgroundFillColorDefault.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.settings, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Configuração OAuth',
                style: FluentTheme.of(
                  context,
                ).typography.subtitle?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Para usar o Google Drive, configure as credenciais OAuth do Google Cloud Console.',
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 12),
          Button(
            onPressed: () => _showOAuthConfigDialog(googleAuth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.lock, size: 18),
                const SizedBox(width: 8),
                const Text('Configurar Credenciais'),
              ],
            ),
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

  Widget _buildDropboxFields() {
    final dropboxAuth = getIt<DropboxAuthProvider>();

    return ListenableBuilder(
      listenable: dropboxAuth,
      builder: (context, _) {
        return Column(
          children: [
            _buildDropboxAuthStatus(dropboxAuth),
            const SizedBox(height: 16),
            if (!dropboxAuth.isSignedIn) ...[
              _buildDropboxOAuthConfigSection(dropboxAuth),
              const SizedBox(height: 16),
            ],
            _buildDropboxFolderFields(dropboxAuth),
            if (!dropboxAuth.isSignedIn) ...[
              const SizedBox(height: 16),
              _buildDropboxNotSignedInWarning(),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDropboxFolderFields(DropboxAuthProvider dropboxAuth) {
    return Column(
      children: [
        AppTextField(
          controller: _dropboxFolderPathController,
          label: 'Caminho da Pasta (opcional)',
          hint: '/Backups ou deixe vazio para raiz',
          prefixIcon: const Icon(FluentIcons.folder),
          enabled: dropboxAuth.isSignedIn,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _dropboxFolderNameController,
          label: 'Nome da Pasta no Dropbox',
          hint: 'Backups',
          prefixIcon: const Icon(FluentIcons.cloud),
          enabled: dropboxAuth.isSignedIn,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Nome da pasta é obrigatório';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDropboxNotSignedInWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorBackground.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.warning, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Conecte-se ao Dropbox para configurar o destino.',
              style: FluentTheme.of(
                context,
              ).typography.caption?.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropboxAuthStatus(DropboxAuthProvider dropboxAuth) {
    final isSignedIn = dropboxAuth.isSignedIn;
    final isLoading = dropboxAuth.isLoading;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSignedIn
            ? AppColors.destinationDropbox.withValues(alpha: 0.1)
            : FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSignedIn
              ? AppColors.destinationDropbox.withValues(alpha: 0.3)
              : FluentTheme.of(
                  context,
                ).resources.controlStrokeColorDefault.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSignedIn
                    ? FluentIcons.check_mark
                    : FluentIcons.cloud_download,
                color: isSignedIn
                    ? AppColors.destinationDropbox
                    : FluentTheme.of(
                        context,
                      ).resources.controlStrokeColorDefault,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSignedIn
                      ? 'Conectado como ${dropboxAuth.currentEmail ?? 'usuário'}'
                      : 'Não conectado ao Dropbox',
                  style: FluentTheme.of(
                    context,
                  ).typography.body?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isSignedIn)
                Button(
                  onPressed: isLoading ? null : () => dropboxAuth.signOut(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.sign_out, size: 18),
                      const SizedBox(width: 8),
                      const Text('Desconectar'),
                    ],
                  ),
                )
              else if (dropboxAuth.isConfigured)
                Button(
                  onPressed: isLoading
                      ? null
                      : () => _connectToDropbox(dropboxAuth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      else
                        const Icon(FluentIcons.signin, size: 18),
                      const SizedBox(width: 8),
                      Text(isLoading ? 'Conectando...' : 'Conectar ao Dropbox'),
                    ],
                  ),
                ),
            ],
          ),
          if (dropboxAuth.error != null) ...[
            const SizedBox(height: 8),
            Text(
              dropboxAuth.error!,
              style: FluentTheme.of(
                context,
              ).typography.caption?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropboxOAuthConfigSection(DropboxAuthProvider dropboxAuth) {
    final isConfigured = dropboxAuth.isConfigured;
    final hasClientId = dropboxAuth.oauthConfig?.clientId.isNotEmpty ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluentTheme.of(
          context,
        ).resources.cardBackgroundFillColorDefault.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.settings, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Configuração OAuth',
                style: FluentTheme.of(
                  context,
                ).typography.subtitle?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isConfigured && hasClientId
                ? 'Credenciais OAuth configuradas. Clique em "Alterar Credenciais" para modificar.'
                : 'Para usar o Dropbox, configure as credenciais OAuth do Dropbox App Console.',
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 12),
          Button(
            onPressed: () => _showDropboxOAuthConfigDialog(dropboxAuth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.lock, size: 18),
                const SizedBox(width: 8),
                Text(isConfigured && hasClientId
                    ? 'Alterar Credenciais'
                    : 'Configurar Credenciais'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectToDropbox(DropboxAuthProvider dropboxAuth) async {
    final success = await dropboxAuth.signIn();
    if (success && mounted) {
      _showSuccess('Conectado ao Dropbox com sucesso!');
    }
  }

  Future<void> _showDropboxOAuthConfigDialog(
    DropboxAuthProvider dropboxAuth,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DropboxOAuthConfigDialog(
        dropboxAuth: dropboxAuth,
        initialClientId: dropboxAuth.oauthConfig?.clientId ?? '',
        initialClientSecret: dropboxAuth.oauthConfig?.clientSecret ?? '',
      ),
    );

    if (result == true && mounted) {
      _showSuccess('Credenciais OAuth configuradas!');
    }
  }

  IconData _getTypeIcon(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return FluentIcons.folder;
      case DestinationType.ftp:
        return FluentIcons.cloud_upload;
      case DestinationType.googleDrive:
        return FluentIcons.cloud;
      case DestinationType.dropbox:
        return FluentIcons.cloud;
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
      case DestinationType.dropbox:
        return 'Dropbox';
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
          final message = failure is Failure
              ? failure.message
              : failure.toString();
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
    MessageModal.showSuccess(context, message: message);
  }

  void _showError(String message) {
    MessageModal.showError(context, message: message);
  }

  void _save() {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    if (_selectedType == DestinationType.googleDrive) {
      final googleAuth = getIt<GoogleAuthProvider>();
      if (!googleAuth.isSignedIn) {
        _showError('Conecte-se ao Google antes de salvar.');
        return;
      }
    }

    if (_selectedType == DestinationType.dropbox) {
      final dropboxAuth = getIt<DropboxAuthProvider>();
      if (!dropboxAuth.isSignedIn) {
        _showError('Conecte-se ao Dropbox antes de salvar.');
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
      case DestinationType.dropbox:
        configJson = jsonEncode({
          'folderPath': _dropboxFolderPathController.text.trim(),
          'folderName': _dropboxFolderNameController.text.trim(),
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
    _clientSecretController = TextEditingController(
      text: widget.initialClientSecret,
    );
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_clientIdController.text.trim().isEmpty) {
      MessageModal.showError(context, message: 'Client ID é obrigatório');
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
    return ContentDialog(
      title: const Row(
        children: [
          Icon(FluentIcons.cloud),
          SizedBox(width: 8),
          Text('Configurar Google OAuth'),
        ],
      ),
      content: SizedBox(
        width: 800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Obtenha as credenciais no Google Cloud Console:',
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 8),
            _buildInstructions(),
            const SizedBox(height: 16),
            AppTextField(
              controller: _clientIdController,
              label: 'Client ID',
              hint: 'xxx.apps.googleusercontent.com',
              prefixIcon: const Icon(FluentIcons.lock),
              enabled: !_isLoading,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Client ID é obrigatório';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _clientSecretController,
              label: 'Client Secret',
              hint: 'GOCSPX-xxx',
              enabled: !_isLoading,
            ),
          ],
        ),
      ),
      actions: [
        CancelButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
        ),
        SaveButton(onPressed: _save, isLoading: _isLoading),
      ],
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1. Acesse console.cloud.google.com',
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            '2. Crie um projeto ou selecione existente',
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            '3. Ative a Google Drive API',
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            '4. Crie credenciais OAuth (Desktop)',
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 4),
          Text(
            '5. Na credencial criada, adicione em "URIs de redirecionamento autorizados":',
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              'http://localhost:8085/oauth2redirect',
              style: FluentTheme.of(context).typography.caption?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nota: localhost é o seu próprio computador. O app cria um servidor temporário automaticamente durante a autenticação.',
            style: FluentTheme.of(context).typography.caption?.copyWith(
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropboxOAuthConfigDialog extends StatefulWidget {
  final DropboxAuthProvider dropboxAuth;
  final String initialClientId;
  final String initialClientSecret;

  const _DropboxOAuthConfigDialog({
    required this.dropboxAuth,
    required this.initialClientId,
    required this.initialClientSecret,
  });

  @override
  State<_DropboxOAuthConfigDialog> createState() =>
      _DropboxOAuthConfigDialogState();
}

class _DropboxOAuthConfigDialogState
    extends State<_DropboxOAuthConfigDialog> {
  late final TextEditingController _clientIdController;
  late final TextEditingController _clientSecretController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController(text: widget.initialClientId);
    _clientSecretController = TextEditingController(
      text: widget.initialClientSecret,
    );
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_clientIdController.text.trim().isEmpty) {
      MessageModal.showError(context, message: 'Client ID é obrigatório');
      return;
    }

    setState(() => _isLoading = true);

    final success = await widget.dropboxAuth.configureOAuth(
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
    return ContentDialog(
      title: const Row(
        children: [
          Icon(FluentIcons.cloud),
          SizedBox(width: 8),
          Text('Configurar Dropbox OAuth'),
        ],
      ),
      content: SizedBox(
        width: 800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Obtenha as credenciais no Dropbox App Console:',
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 8),
            _buildInstructions(),
            const SizedBox(height: 16),
            AppTextField(
              controller: _clientIdController,
              label: 'App Key',
              hint: 'xxxxx',
              prefixIcon: const Icon(FluentIcons.lock),
              enabled: !_isLoading,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'App Key é obrigatório';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _clientSecretController,
              label: 'App Secret',
              hint: 'xxxxx',
              enabled: !_isLoading,
            ),
          ],
        ),
      ),
      actions: [
        CancelButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
        ),
        SaveButton(onPressed: _save, isLoading: _isLoading),
      ],
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1. Acesse dropbox.com/developers/apps',
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            '2. Clique em "Create app"',
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            '3. Escolha "Scoped access" e "Full Dropbox"',
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            '4. Configure os scopes: files.content.write, files.content.read, account_info.read',
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 4),
          Text(
            '5. Na seção "OAuth 2", adicione em "Redirect URIs":',
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              'http://localhost:8085/oauth2redirect',
              style: FluentTheme.of(context).typography.caption?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nota: localhost é o seu próprio computador. O app cria um servidor temporário automaticamente durante a autenticação.',
            style: FluentTheme.of(context).typography.caption?.copyWith(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}
