import 'dart:convert';

import 'package:backup_database/application/providers/dropbox_auth_provider.dart';
import 'package:backup_database/application/providers/google_auth_provider.dart';
import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud.dart'
    as nextcloud;
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class DestinationDialog extends StatefulWidget {
  const DestinationDialog({super.key, this.destination});
  final BackupDestination? destination;

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

  final _localPathController = TextEditingController();
  bool _createSubfoldersByDate = true;

  final _ftpHostController = TextEditingController();
  final _ftpPortController = TextEditingController(text: '21');
  final _ftpUsernameController = TextEditingController();
  final _ftpPasswordController = TextEditingController();
  final _ftpRemotePathController = TextEditingController(text: '/backups');
  bool _useFtps = false;

  final _googleFolderNameController = TextEditingController(text: 'Backups');

  final _dropboxFolderPathController = TextEditingController();
  final _dropboxFolderNameController = TextEditingController(text: 'Backups');

  final _nextcloudServerUrlController = TextEditingController();
  final _nextcloudUsernameController = TextEditingController();
  final _nextcloudAppPasswordController = TextEditingController();
  final _nextcloudRemotePathController = TextEditingController(text: '/');
  final _nextcloudFolderNameController = TextEditingController(text: 'Backups');
  bool _nextcloudAllowInvalidCertificates = false;
  NextcloudAuthMode _nextcloudAuthMode = NextcloudAuthMode.appPassword;

  final _retentionDaysController = TextEditingController(text: '7');
  bool _isEnabled = true;
  bool _isTestingFtpConnection = false;
  bool _isTestingNextcloudConnection = false;

  bool get isEditing => widget.destination != null;

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

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
          _localPathController.text = (config['path'] as String?) ?? '';
          _createSubfoldersByDate =
              (config['createSubfoldersByDate'] as bool?) ?? true;
          _retentionDaysController.text =
              ((config['retentionDays'] as int?) ?? 7).toString();
        case DestinationType.ftp:
          _ftpHostController.text = (config['host'] as String?) ?? '';
          _ftpPortController.text = ((config['port'] as int?) ?? 21).toString();
          _ftpUsernameController.text = (config['username'] as String?) ?? '';
          _ftpPasswordController.text = (config['password'] as String?) ?? '';
          _ftpRemotePathController.text =
              (config['remotePath'] as String?) ?? '/backups';
          _useFtps = (config['useFtps'] as bool?) ?? false;
          _retentionDaysController.text =
              ((config['retentionDays'] as int?) ?? 7).toString();
        case DestinationType.googleDrive:
          _googleFolderNameController.text =
              (config['folderName'] as String?) ?? 'Backups';
          _retentionDaysController.text =
              ((config['retentionDays'] as int?) ?? 7).toString();
        case DestinationType.dropbox:
          _dropboxFolderPathController.text =
              (config['folderPath'] as String?) ?? '';
          _dropboxFolderNameController.text =
              (config['folderName'] as String?) ?? 'Backups';
          _retentionDaysController.text =
              ((config['retentionDays'] as int?) ?? 7).toString();
        case DestinationType.nextcloud:
          _nextcloudServerUrlController.text =
              (config['serverUrl'] as String?) ?? '';
          _nextcloudUsernameController.text =
              (config['username'] as String?) ?? '';
          _nextcloudAppPasswordController.text = EncryptionService.decrypt(
            (config['appPassword'] as String?) ?? '',
          );
          _nextcloudAuthMode = NextcloudAuthMode.values.firstWhere(
            (e) => e.name == ((config['authMode'] as String?) ?? ''),
            orElse: () => NextcloudAuthMode.appPassword,
          );
          _nextcloudRemotePathController.text =
              (config['remotePath'] as String?) ?? '/';
          _nextcloudFolderNameController.text =
              (config['folderName'] as String?) ?? 'Backups';
          _nextcloudAllowInvalidCertificates =
              (config['allowInvalidCertificates'] as bool?) ?? false;
          _retentionDaysController.text =
              ((config['retentionDays'] as int?) ?? 7).toString();
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
    _nextcloudServerUrlController.dispose();
    _nextcloudUsernameController.dispose();
    _nextcloudAppPasswordController.dispose();
    _nextcloudRemotePathController.dispose();
    _nextcloudFolderNameController.dispose();
    _retentionDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(
        minWidth: 600,
        maxWidth: 600,
        maxHeight: 800,
      ),
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
          isEditing
              ? _t('Editar destino', 'Edit destination')
              : _t('Novo destino', 'New destination'),
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
              Consumer<LicenseProvider>(
                builder: (context, licenseProvider, child) {
                  final hasGoogleDrive =
                      licenseProvider.hasValidLicense &&
                      licenseProvider.currentLicense!.hasFeature(
                        LicenseFeatures.googleDrive,
                      );
                  final hasDropbox =
                      licenseProvider.hasValidLicense &&
                      licenseProvider.currentLicense!.hasFeature(
                        LicenseFeatures.dropbox,
                      );
                  final hasNextcloud =
                      licenseProvider.hasValidLicense &&
                      licenseProvider.currentLicense!.hasFeature(
                        LicenseFeatures.nextcloud,
                      );

                  final isGoogleDriveBlocked =
                      _selectedType == DestinationType.googleDrive &&
                      !hasGoogleDrive;
                  final isDropboxBlocked =
                      _selectedType == DestinationType.dropbox && !hasDropbox;
                  final isNextcloudBlocked =
                      _selectedType == DestinationType.nextcloud &&
                      !hasNextcloud;

                  if (isGoogleDriveBlocked ||
                      isDropboxBlocked ||
                      isNextcloudBlocked) {
                    return InfoBar(
                      severity: InfoBarSeverity.warning,
                      title: Text(_t('Recurso bloqueado', 'Feature blocked')),
                      content: const Text(
                        'Este destino requer uma licença válida. '
                        'Acesse Configurações > Licenciamento para mais informações.',
                      ),
                      action: Button(
                        child: Text(_t('Ver licenciamento', 'View licensing')),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
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
    return Consumer<LicenseProvider>(
      builder: (context, licenseProvider, child) {
        final hasGoogleDrive =
            licenseProvider.hasValidLicense &&
            licenseProvider.currentLicense!.hasFeature(
              LicenseFeatures.googleDrive,
            );
        final hasDropbox =
            licenseProvider.hasValidLicense &&
            licenseProvider.currentLicense!.hasFeature(LicenseFeatures.dropbox);
        final hasNextcloud =
            licenseProvider.hasValidLicense &&
            licenseProvider.currentLicense!.hasFeature(
              LicenseFeatures.nextcloud,
            );

        return AppDropdown<DestinationType>(
          label: _t('Tipo de destino', 'Destination type'),
          value: _selectedType,
          placeholder: Text(_t('Tipo de destino', 'Destination type')),
          items: DestinationType.values.map((type) {
            final isGoogleDriveBlocked =
                type == DestinationType.googleDrive && !hasGoogleDrive;
            final isDropboxBlocked =
                type == DestinationType.dropbox && !hasDropbox;
            final isNextcloudBlocked =
                type == DestinationType.nextcloud && !hasNextcloud;
            final isBlocked =
                isGoogleDriveBlocked || isDropboxBlocked || isNextcloudBlocked;

            return ComboBoxItem<DestinationType>(
              value: type,
              enabled: !isBlocked,
              child: Row(
                children: [
                  Icon(
                    _getTypeIcon(type),
                    size: 20,
                    color: isBlocked
                        ? FluentTheme.of(context)
                              .resources
                              .controlStrokeColorDefault
                              .withValues(alpha: 0.4)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            isBlocked
                                ? '${_getTypeName(type)} (${_t('Requer licença', 'License required')})'
                                : _getTypeName(type),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              color: isBlocked
                                  ? FluentTheme.of(context)
                                        .resources
                                        .controlStrokeColorDefault
                                        .withValues(alpha: 0.4)
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isBlocked) ...[
                          const SizedBox(width: 8),
                          Icon(
                            FluentIcons.lock,
                            size: 16,
                            color: FluentTheme.of(context)
                                .resources
                                .controlStrokeColorDefault
                                .withValues(alpha: 0.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: isEditing
              ? null
              : (value) {
                  if (value != null) {
                    final isGoogleDriveBlocked =
                        value == DestinationType.googleDrive && !hasGoogleDrive;
                    final isDropboxBlocked =
                        value == DestinationType.dropbox && !hasDropbox;
                    final isNextcloudBlocked =
                        value == DestinationType.nextcloud && !hasNextcloud;

                    if (isGoogleDriveBlocked ||
                        isDropboxBlocked ||
                        isNextcloudBlocked) {
                      MessageModal.showWarning(
                        context,
                        message: _t(
                          'Este destino requer uma licença válida. Acesse Configurações > Licenciamento para mais informações.',
                          'This destination requires a valid license. Go to Settings > Licensing for more information.',
                        ),
                      );
                      return;
                    }

                    setState(() {
                      _selectedType = value;
                    });
                  }
                },
        );
      },
    );
  }

  Widget _buildNameField() {
    return AppTextField(
      controller: _nameController,
      label: _t('Nome do destino', 'Destination name'),
      hint: _t(
        'Ex: Backup local, FTP servidor, Google Drive, Dropbox',
        'Ex: Local backup, FTP server, Google Drive, Dropbox',
      ),
      prefixIcon: const Icon(FluentIcons.tag),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return _t('Nome é obrigatório', 'Name is required');
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
    } else if (_selectedType == DestinationType.dropbox) {
      return _buildDropboxFields();
    } else {
      return _buildNextcloudFields();
    }
  }

  Widget _buildNextcloudFields() {
    return Column(
      children: [
        AppTextField(
          controller: _nextcloudServerUrlController,
          label: _t('URL do Nextcloud', 'Nextcloud URL'),
          hint: 'https://cloud.exemplo.com',
          prefixIcon: const Icon(FluentIcons.globe),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return _t('URL e obrigatoria', 'URL is required');

            final uri = Uri.tryParse(text);
            if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
              return _t('URL invalida', 'Invalid URL');
            }
            if (uri.scheme != 'https' && uri.scheme != 'http') {
              return _t('Use http ou https', 'Use http or https');
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _nextcloudUsernameController,
          label: _t('Usuario', 'Username'),
          hint: 'usuario',
          prefixIcon: const Icon(FluentIcons.contact),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _t('Usuário é obrigatório', 'Username is required');
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        AppDropdown<NextcloudAuthMode>(
          label: _t('Tipo de credencial', 'Credential type'),
          value: _nextcloudAuthMode,
          placeholder: Text(_t('Tipo de credencial', 'Credential type')),
          items: NextcloudAuthMode.values.map((mode) {
            final label = mode == NextcloudAuthMode.appPassword
                ? _t('App Password (recomendado)', 'App Password (recommended)')
                : _t('Senha do usuario', 'User password');
            return ComboBoxItem<NextcloudAuthMode>(
              value: mode,
              child: Text(label),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _nextcloudAuthMode = value;
            });
          },
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _nextcloudAppPasswordController,
          label: _nextcloudAuthMode == NextcloudAuthMode.appPassword
              ? _t('App Password', 'App Password')
              : _t('Senha do usuario', 'User password'),
          hint: _nextcloudAuthMode == NextcloudAuthMode.appPassword
              ? _t('Senha de aplicativo do Nextcloud', 'Nextcloud app password')
              : _t('Senha do usuario do Nextcloud', 'Nextcloud user password'),
          prefixIcon: const Icon(FluentIcons.lock),
          obscureText: true,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return _nextcloudAuthMode == NextcloudAuthMode.appPassword
                  ? _t('App Password é obrigatório', 'App Password is required')
                  : _t(
                      'Senha do usuario e obrigatoria',
                      'User password is required',
                    );
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _nextcloudRemotePathController,
          label: _t('Caminho remoto (opcional)', 'Remote path (optional)'),
          hint: '/ ou /Backups',
          prefixIcon: const Icon(FluentIcons.folder),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _nextcloudFolderNameController,
          label: _t('Nome da pasta', 'Folder name'),
          hint: 'Backups',
          prefixIcon: const Icon(FluentIcons.cloud),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _t(
                'Nome da pasta é obrigatório',
                'Folder name is required',
              );
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoLabel(
              label: _t(
                'Permitir certificado invalido (self-signed)',
                'Allow invalid certificate (self-signed)',
              ),
              child: ToggleSwitch(
                checked: _nextcloudAllowInvalidCertificates,
                onChanged: _setNextcloudAllowInvalidCertificates,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Use apenas se seu Nextcloud usa certificado self-signed ou CA interna.',
                'Use only if your Nextcloud uses self-signed cert or internal CA.',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ActionButton(
          label: _t('Testar conexão Nextcloud', 'Test Nextcloud connection'),
          icon: FluentIcons.network_tower,
          onPressed: _testNextcloudConnection,
          isLoading: _isTestingNextcloudConnection,
        ),
      ],
    );
  }

  Future<void> _setNextcloudAllowInvalidCertificates(bool value) async {
    if (!value) {
      setState(() => _nextcloudAllowInvalidCertificates = false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(_t('Atenção', 'Attention')),
        content: Text(
          _t(
            'Permitir certificado inválido reduz a segurança da conexão.\nHabilite apenas se o servidor usa certificado self-signed ou CA interna.',
            'Allowing invalid certificate reduces connection security.\nEnable only if server uses self-signed cert or internal CA.',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('Habilitar', 'Enable')),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      setState(() => _nextcloudAllowInvalidCertificates = true);
    }
  }

  Widget _buildRetentionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NumericField(
          controller: _retentionDaysController,
          label: _t('Dias de retencao', 'Retention days'),
          hint: _t(
            'Ex: 7 (mantem backups por 7 dias)',
            'Ex: 7 (keeps backups for 7 days)',
          ),
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
          const Icon(FluentIcons.info, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _retentionDaysController,
              builder: (context, value, child) {
                final days = int.tryParse(value.text) ?? 7;
                final cutoffDate = DateTime.now().subtract(
                  Duration(days: days),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('Limpeza automatica', 'Automatic cleanup'),
                      style: FluentTheme.of(context).typography.caption
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        'Backups anteriores a ${_formatDate(cutoffDate)} serao excluidos automaticamente apos cada backup executado.',
                        'Backups older than ${_formatDate(cutoffDate)} will be automatically removed after each backup run.',
                      ),
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
      label: _t('Criar subpastas por data', 'Create date-based subfolders'),
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
          label: _t('Usar FTPS', 'Use FTPS'),
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
          _t('Conexão FTP segura (SSL/TLS)', 'Secure FTP connection (SSL/TLS)'),
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        ActionButton(
          label: _t('Testar conexão FTP', 'Test FTP connection'),
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
            'Destino ativo para uso em agendamentos',
            'Destination active for schedule use',
          ),
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
                label: _t('Caminho da pasta', 'Folder path'),
                hint: r'C:\Backups',
                prefixIcon: const Icon(FluentIcons.folder),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _t('Caminho é obrigatório', 'Path is required');
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
                label: _t('Servidor FTP', 'FTP server'),
                hint: 'ftp.exemplo.com',
                prefixIcon: const Icon(FluentIcons.server),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _t('Servidor é obrigatório', 'Server is required');
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: NumericField(
                controller: _ftpPortController,
                label: _t('Porta', 'Port'),
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
          label: _t('Usuario', 'Username'),
          hint: 'usuario_ftp',
          prefixIcon: const Icon(FluentIcons.contact),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _t('Usuário é obrigatório', 'Username is required');
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        PasswordField(
          controller: _ftpPasswordController,
          label: _t('Senha FTP', 'FTP password'),
          hint: _t('Senha do FTP', 'FTP password'),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _ftpRemotePathController,
          label: _t('Caminho remoto', 'Remote path'),
          hint: '/backups',
          prefixIcon: const Icon(FluentIcons.folder),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _t(
                'Caminho remoto é obrigatório',
                'Remote path is required',
              );
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
      label: _t('Nome da pasta no Google Drive', 'Google Drive folder name'),
      hint: 'Backups',
      prefixIcon: const Icon(FluentIcons.cloud),
      enabled: googleAuth.isSignedIn,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return _t('Nome da pasta é obrigatório', 'Folder name is required');
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
          const Icon(FluentIcons.warning, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _t(
                'Conecte-se ao Google para configurar o destino.',
                'Sign in to Google to configure this destination.',
              ),
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
                      ? _t(
                          'Conectado como ${googleAuth.currentEmail ?? 'usuario'}',
                          'Connected as ${googleAuth.currentEmail ?? 'user'}',
                        )
                      : _t(
                          'Nao conectado ao Google',
                          'Not connected to Google',
                        ),
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
                      Text(_t('Desconectar', 'Disconnect')),
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
                      Text(
                        isLoading
                            ? _t('Conectando...', 'Connecting...')
                            : _t('Conectar ao Google', 'Connect to Google'),
                      ),
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
              const Icon(
                FluentIcons.settings,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _t('Configuração OAuth', 'OAuth configuration'),
                style: FluentTheme.of(
                  context,
                ).typography.subtitle?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'Para usar o Google Drive, configure as credenciais OAuth do Google Cloud Console.',
              'To use Google Drive, configure OAuth credentials in Google Cloud Console.',
            ),
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
                Text(_t('Configurar credenciais', 'Configure credentials')),
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
      _showSuccess(
        _t(
          'Conectado ao Google com sucesso!',
          'Connected to Google successfully!',
        ),
      );
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

    if ((result ?? false) && mounted) {
      _showSuccess(
        _t('Credenciais OAuth configuradas!', 'OAuth credentials configured!'),
      );
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
          label: _t('Caminho da pasta (opcional)', 'Folder path (optional)'),
          hint: _t(
            '/Backups ou deixe vazio para raiz',
            '/Backups or leave empty for root',
          ),
          prefixIcon: const Icon(FluentIcons.folder),
          enabled: dropboxAuth.isSignedIn,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _dropboxFolderNameController,
          label: _t('Nome da pasta no Dropbox', 'Dropbox folder name'),
          hint: 'Backups',
          prefixIcon: const Icon(FluentIcons.cloud),
          enabled: dropboxAuth.isSignedIn,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _t(
                'Nome da pasta é obrigatório',
                'Folder name is required',
              );
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
          const Icon(FluentIcons.warning, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _t(
                'Conecte-se ao Dropbox para configurar o destino.',
                'Sign in to Dropbox to configure this destination.',
              ),
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
                      ? _t(
                          'Conectado como ${dropboxAuth.currentEmail ?? 'usuario'}',
                          'Connected as ${dropboxAuth.currentEmail ?? 'user'}',
                        )
                      : _t(
                          'Nao conectado ao Dropbox',
                          'Not connected to Dropbox',
                        ),
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
                      Text(_t('Desconectar', 'Disconnect')),
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
                      Text(
                        isLoading
                            ? _t('Conectando...', 'Connecting...')
                            : _t('Conectar ao Dropbox', 'Connect to Dropbox'),
                      ),
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
              const Icon(
                FluentIcons.settings,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _t('Configuração OAuth', 'OAuth configuration'),
                style: FluentTheme.of(
                  context,
                ).typography.subtitle?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isConfigured && hasClientId
                ? _t(
                    'Credenciais OAuth configuradas. Clique em "Alterar credenciais" para modificar.',
                    'OAuth credentials configured. Click "Change credentials" to modify.',
                  )
                : _t(
                    'Para usar o Dropbox, configure as credenciais OAuth do Dropbox App Console.',
                    'To use Dropbox, configure OAuth credentials in Dropbox App Console.',
                  ),
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
                Text(
                  isConfigured && hasClientId
                      ? _t('Alterar credenciais', 'Change credentials')
                      : _t('Configurar credenciais', 'Configure credentials'),
                ),
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
      _showSuccess(
        _t(
          'Conectado ao Dropbox com sucesso!',
          'Connected to Dropbox successfully!',
        ),
      );
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

    if ((result ?? false) && mounted) {
      _showSuccess(
        _t('Credenciais OAuth configuradas!', 'OAuth credentials configured!'),
      );
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
      case DestinationType.nextcloud:
        return FluentIcons.cloud;
    }
  }

  String _getTypeName(DestinationType type) {
    switch (type) {
      case DestinationType.local:
        return _t('Pasta local', 'Local folder');
      case DestinationType.ftp:
        return _t('Servidor FTP', 'FTP server');
      case DestinationType.googleDrive:
        return 'Google Drive';
      case DestinationType.dropbox:
        return 'Dropbox';
      case DestinationType.nextcloud:
        return 'Nextcloud';
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
      dialogTitle: _t(
        'Selecionar pasta de destino',
        'Select destination folder',
      ),
    );
    if (result != null) {
      setState(() {
        _localPathController.text = result;
      });
    }
  }

  Future<void> _testFtpConnection() async {
    if (_ftpHostController.text.trim().isEmpty) {
      _showError(_t('Servidor FTP é obrigatório', 'FTP server is required'));
      return;
    }
    if (_ftpPortController.text.trim().isEmpty) {
      _showError(_t('Porta e obrigatoria', 'Port is required'));
      return;
    }
    if (_ftpUsernameController.text.trim().isEmpty) {
      _showError(_t('Usuário é obrigatório', 'Username is required'));
      return;
    }
    if (_ftpPasswordController.text.trim().isEmpty) {
      _showError(_t('Senha e obrigatoria', 'Password is required'));
      return;
    }

    setState(() {
      _isTestingFtpConnection = true;
    });

    try {
      final port = int.tryParse(_ftpPortController.text.trim());
      if (port == null || port < 1 || port > 65535) {
        _showError(
          _t(
            'Porta invalida. Use um valor entre 1 e 65535',
            'Invalid port. Use a value between 1 and 65535',
          ),
        );
        return;
      }

      final config = FtpDestinationConfig(
        host: _ftpHostController.text.trim(),
        port: port,
        username: _ftpUsernameController.text.trim(),
        password: _ftpPasswordController.text,
        remotePath: _ftpRemotePathController.text.trim(),
        useFtps: _useFtps,
      );

      final ftpService = getIt<IFtpService>();
      final result = await ftpService.testConnection(config);

      result.fold(
        (success) {
          if (success) {
            _showSuccess(
              _t(
                'Conexão FTP estabelecida com sucesso!',
                'FTP connection established successfully!',
              ),
            );
          } else {
            _showError(
              _t(
                'Falha ao conectar ao servidor FTP',
                'Failed to connect to FTP server',
              ),
            );
          }
        },
        (failure) {
          final message = failure is Failure
              ? failure.message
              : failure.toString();
          _showError(
            _t(
              'Erro ao testar conexão FTP:\n$message',
              'Error testing FTP connection:\n$message',
            ),
          );
        },
      );
    } on Object catch (e) {
      _showError(_t('Erro inesperado: $e', 'Unexpected error: $e'));
    } finally {
      setState(() {
        _isTestingFtpConnection = false;
      });
    }
  }

  Future<void> _testNextcloudConnection() async {
    if (_nextcloudServerUrlController.text.trim().isEmpty) {
      _showError(
        _t('URL do Nextcloud e obrigatoria', 'Nextcloud URL is required'),
      );
      return;
    }
    if (_nextcloudUsernameController.text.trim().isEmpty) {
      _showError(_t('Usuário é obrigatório', 'Username is required'));
      return;
    }
    if (_nextcloudAppPasswordController.text.trim().isEmpty) {
      _showError(
        _nextcloudAuthMode == NextcloudAuthMode.appPassword
            ? _t('App Password é obrigatório', 'App Password is required')
            : _t('Senha do usuario e obrigatoria', 'User password is required'),
      );
      return;
    }

    setState(() {
      _isTestingNextcloudConnection = true;
    });

    try {
      final config = NextcloudDestinationConfig(
        serverUrl: _nextcloudServerUrlController.text.trim(),
        username: _nextcloudUsernameController.text.trim(),
        appPassword: EncryptionService.encrypt(
          _nextcloudAppPasswordController.text,
        ),
        authMode: _nextcloudAuthMode,
        remotePath: _nextcloudRemotePathController.text.trim(),
        folderName: _nextcloudFolderNameController.text.trim(),
        allowInvalidCertificates: _nextcloudAllowInvalidCertificates,
      );

      final nextcloudService = getIt<nextcloud.NextcloudDestinationService>();
      final result = await nextcloudService.testConnection(config);

      result.fold(
        (success) {
          if (success) {
            _showSuccess(
              _t(
                'Conexão Nextcloud estabelecida com sucesso!',
                'Nextcloud connection established successfully!',
              ),
            );
          } else {
            _showError(
              _t(
                'Falha ao conectar ao servidor Nextcloud',
                'Failed to connect to Nextcloud server',
              ),
            );
          }
        },
        (failure) {
          final message = failure is Failure
              ? failure.message
              : failure.toString();
          _showError(
            _t(
              'Erro ao testar conexão Nextcloud:\n$message',
              'Error testing Nextcloud connection:\n$message',
            ),
          );
        },
      );
    } on Object catch (e) {
      _showError(_t('Erro inesperado: $e', 'Unexpected error: $e'));
    } finally {
      setState(() {
        _isTestingNextcloudConnection = false;
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
        _showError(
          _t(
            'Conecte-se ao Google antes de salvar.',
            'Connect to Google before saving.',
          ),
        );
        return;
      }
    }

    if (_selectedType == DestinationType.dropbox) {
      final dropboxAuth = getIt<DropboxAuthProvider>();
      if (!dropboxAuth.isSignedIn) {
        _showError(
          _t(
            'Conecte-se ao Dropbox antes de salvar.',
            'Connect to Dropbox before saving.',
          ),
        );
        return;
      }
    }

    if (_selectedType == DestinationType.nextcloud) {
      final licenseProvider = context.read<LicenseProvider>();
      final hasNextcloud =
          licenseProvider.hasValidLicense &&
          licenseProvider.currentLicense!.hasFeature(LicenseFeatures.nextcloud);
      if (!hasNextcloud) {
        _showError(
          _t(
            'Este destino requer uma licença válida. Acesse Configurações > Licenciamento.',
            'This destination requires a valid license. Go to Settings > Licensing.',
          ),
        );
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
      case DestinationType.googleDrive:
        configJson = jsonEncode({
          'folderName': _googleFolderNameController.text.trim(),
          'folderId': 'root',
          'retentionDays': retentionDays,
        });
      case DestinationType.dropbox:
        configJson = jsonEncode({
          'folderPath': _dropboxFolderPathController.text.trim(),
          'folderName': _dropboxFolderNameController.text.trim(),
          'retentionDays': retentionDays,
        });
      case DestinationType.nextcloud:
        configJson = jsonEncode({
          'serverUrl': _nextcloudServerUrlController.text.trim(),
          'username': _nextcloudUsernameController.text.trim(),
          'appPassword': EncryptionService.encrypt(
            _nextcloudAppPasswordController.text,
          ),
          'authMode': _nextcloudAuthMode.name,
          'remotePath': _nextcloudRemotePathController.text.trim(),
          'folderName': _nextcloudFolderNameController.text.trim(),
          'allowInvalidCertificates': _nextcloudAllowInvalidCertificates,
          'retentionDays': retentionDays,
        });
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
  const _OAuthConfigDialog({
    required this.googleAuth,
    required this.initialClientId,
    required this.initialClientSecret,
  });
  final GoogleAuthProvider googleAuth;
  final String initialClientId;
  final String initialClientSecret;

  @override
  State<_OAuthConfigDialog> createState() => _OAuthConfigDialogState();
}

class _OAuthConfigDialogState extends State<_OAuthConfigDialog> {
  late final TextEditingController _clientIdController;
  late final TextEditingController _clientSecretController;
  bool _isLoading = false;

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

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
      MessageModal.showError(
        context,
        message: _t('Client ID é obrigatório', 'Client ID is required'),
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
    return ContentDialog(
      title: Row(
        children: [
          const Icon(FluentIcons.cloud),
          const SizedBox(width: 8),
          Text(_t('Configurar Google OAuth', 'Configure Google OAuth')),
        ],
      ),
      content: SizedBox(
        width: 800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                'Obtenha as credenciais no Google Cloud Console:',
                'Get credentials from Google Cloud Console:',
              ),
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
                  return _t('Client ID é obrigatório', 'Client ID is required');
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
            _t(
              '1. Acesse console.cloud.google.com',
              '1. Go to console.cloud.google.com',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            _t(
              '2. Crie um projeto ou selecione existente',
              '2. Create a project or select an existing one',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            _t('3. Ative a Google Drive API', '3. Enable Google Drive API'),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            _t(
              '4. Crie credenciais OAuth (Desktop)',
              '4. Create OAuth credentials (Desktop)',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              '5. Na credencial criada, adicione em "URIs de redirecionamento autorizados":',
              '5. In the created credential, add this under "Authorized redirect URIs":',
            ),
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
            _t(
              'Nota: localhost é o seu próprio computador. O app cria um servidor temporário automaticamente durante a autenticação.',
              'Note: localhost is your own machine. The app creates a temporary local server during authentication.',
            ),
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
  const _DropboxOAuthConfigDialog({
    required this.dropboxAuth,
    required this.initialClientId,
    required this.initialClientSecret,
  });
  final DropboxAuthProvider dropboxAuth;
  final String initialClientId;
  final String initialClientSecret;

  @override
  State<_DropboxOAuthConfigDialog> createState() =>
      _DropboxOAuthConfigDialogState();
}

class _DropboxOAuthConfigDialogState extends State<_DropboxOAuthConfigDialog> {
  late final TextEditingController _clientIdController;
  late final TextEditingController _clientSecretController;
  bool _isLoading = false;

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

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
      MessageModal.showError(
        context,
        message: _t('Client ID é obrigatório', 'Client ID is required'),
      );
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
      title: Row(
        children: [
          const Icon(FluentIcons.cloud),
          const SizedBox(width: 8),
          Text(_t('Configurar Dropbox OAuth', 'Configure Dropbox OAuth')),
        ],
      ),
      content: SizedBox(
        width: 800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                'Obtenha as credenciais no Dropbox App Console:',
                'Get credentials from Dropbox App Console:',
              ),
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
                  return _t('App Key é obrigatório', 'App Key is required');
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
            _t(
              '1. Acesse dropbox.com/developers/apps',
              '1. Go to dropbox.com/developers/apps',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            _t('2. Clique em "Create app"', '2. Click "Create app"'),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            _t(
              '3. Escolha "Scoped access" e "Full Dropbox"',
              '3. Choose "Scoped access" and "Full Dropbox"',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            _t(
              '4. Configure os scopes: files.content.write, files.content.read, account_info.read',
              '4. Configure scopes: files.content.write, files.content.read, account_info.read',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              '5. Na secao "OAuth 2", adicione em "Redirect URIs":',
              '5. In section "OAuth 2", add this in "Redirect URIs":',
            ),
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
            _t(
              'Nota: localhost é o seu próprio computador. O app cria um servidor temporário automaticamente durante a autenticação.',
              'Note: localhost is your own machine. The app creates a temporary local server during authentication.',
            ),
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
