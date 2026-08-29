import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/providers/dropbox_auth_provider.dart';
import 'package:backup_database/application/providers/google_auth_provider.dart';
import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_behavior.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_dropbox_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_dropbox_oauth_dialog.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_ftp_advanced.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_ftp_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_google_drive_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_google_oauth_dialog.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_identity.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_local_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_nextcloud_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_oauth_credentials_card.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_oauth_status_card.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_type_meta.dart';
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
      builder: (BuildContext context) =>
          DestinationDialog(destination: destination),
    );
  }

  @override
  State<DestinationDialog> createState() => _DestinationDialogState();
}

class _DestinationDialogState extends State<DestinationDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late DestinationType _selectedType;
  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _localPathController = TextEditingController();
  bool _createSubfoldersByDate = true;

  final TextEditingController _ftpHostController = TextEditingController();
  final TextEditingController _ftpPortController = TextEditingController(
    text: '21',
  );
  final TextEditingController _ftpUsernameController = TextEditingController();
  final TextEditingController _ftpPasswordController = TextEditingController();
  final TextEditingController _ftpRemotePathController = TextEditingController(
    text: '/backups',
  );
  bool _useFtps = false;
  bool _enableResumeFtp = true;
  bool _keepPartOnCancelFtp = true;
  bool _ftpAllowInvalidCertificates = true;
  FtpWhenResumeNotSupported _whenResumeNotSupportedFtp =
      FtpWhenResumeNotSupported.fallback;
  bool _enableVerboseLogFtp = false;
  bool _enableStrongIntegrityValidationFtp = false;
  bool _enableReadBackValidationFtp = false;
  FtpIntegrityPreset _ftpIntegrityPreset = FtpIntegrityPreset.quick;
  final TextEditingController _connectionTimeoutSecondsController =
      TextEditingController();
  final TextEditingController _uploadTimeoutMinutesController =
      TextEditingController();
  final TextEditingController _maxAttemptsFtpController =
      TextEditingController();

  final TextEditingController _googleFolderNameController =
      TextEditingController(text: 'Backups');

  final TextEditingController _dropboxFolderPathController =
      TextEditingController();
  final TextEditingController _dropboxFolderNameController =
      TextEditingController(text: 'Backups');

  final TextEditingController _nextcloudServerUrlController =
      TextEditingController();
  final TextEditingController _nextcloudUsernameController =
      TextEditingController();
  final TextEditingController _nextcloudAppPasswordController =
      TextEditingController();
  final TextEditingController _nextcloudRemotePathController =
      TextEditingController(text: '/');
  final TextEditingController _nextcloudFolderNameController =
      TextEditingController(text: 'Backups');
  bool _nextcloudAllowInvalidCertificates = false;
  NextcloudAuthMode _nextcloudAuthMode = NextcloudAuthMode.appPassword;

  final TextEditingController _retentionDaysController = TextEditingController(
    text: '7',
  );
  bool _isEnabled = true;
  bool _isTestingFtpConnection = false;
  bool _isTestingNextcloudConnection = false;

  bool get isEditing => widget.destination != null;

  String _dialogLabel(String ptBr, String enUs) {
    if (!mounted) return enUs;
    return destinationDialogLabel(context, ptBr, enUs);
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
          _enableResumeFtp = (config['enableResume'] as bool?) ?? true;
          _keepPartOnCancelFtp = (config['keepPartOnCancel'] as bool?) ?? true;
          _whenResumeNotSupportedFtp = parseFtpWhenResumeNotSupported(
            config['whenResumeNotSupported'] as String?,
          );
          _enableVerboseLogFtp = (config['enableVerboseLog'] as bool?) ?? false;
          _enableStrongIntegrityValidationFtp =
              (config['enableStrongIntegrityValidation'] as bool?) ?? false;
          _enableReadBackValidationFtp =
              (config['enableReadBackValidation'] as bool?) ?? false;
          _ftpAllowInvalidCertificates =
              (config['allowInvalidCertificates'] as bool?) ?? true;
          _ftpIntegrityPreset = FtpIntegrityPresetX.fromFlags(
            enableStrongIntegrityValidation:
                _enableStrongIntegrityValidationFtp,
            enableReadBackValidation: _enableReadBackValidationFtp,
          );
          final maxAttempts = config['maxAttempts'] as int?;
          _maxAttemptsFtpController.text = maxAttempts != null
              ? maxAttempts.toString()
              : '';
          final connTimeout = config['connectionTimeoutSeconds'] as int?;
          _connectionTimeoutSecondsController.text = connTimeout != null
              ? connTimeout.toString()
              : '';
          final uploadTimeout = config['uploadTimeoutMinutes'] as int?;
          _uploadTimeoutMinutesController.text = uploadTimeout != null
              ? uploadTimeout.toString()
              : '';
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
            (NextcloudAuthMode e) =>
                e.name == ((config['authMode'] as String?) ?? ''),
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
    _connectionTimeoutSecondsController.dispose();
    _uploadTimeoutMinutesController.dispose();
    _maxAttemptsFtpController.dispose();
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
    return AppDialogShell(
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
        Icon(
          DestinationDialogTypeMeta.iconOf(_selectedType),
          color: DestinationDialogTypeMeta.colorOf(_selectedType),
        ),
        const SizedBox(width: 12),
        Text(
          isEditing
              ? _dialogLabel('Editar destino', 'Edit destination')
              : _dialogLabel('Novo destino', 'New destination'),
          style: FluentTheme.of(context).typography.title,
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DestinationDialogIdentitySection(
            selectedType: _selectedType,
            isEditing: isEditing,
            nameController: _nameController,
            labelBuilder: _dialogLabel,
            onTypeChanged: (DestinationType value) {
              setState(() {
                _selectedType = value;
              });
            },
          ),
          const SizedBox(height: AppSpacing.md),
          AppSectionCard(
            title: DestinationDialogTypeMeta.sectionTitle(
              _selectedType,
              _dialogLabel,
            ),
            description: DestinationDialogTypeMeta.sectionDescription(
              _selectedType,
              _dialogLabel,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTypeSpecificFields(),
                if (_selectedType == DestinationType.ftp) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildFtpsSection(),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DestinationDialogBehaviorSection(
            selectedType: _selectedType,
            retentionDaysController: _retentionDaysController,
            createSubfoldersByDate: _createSubfoldersByDate,
            isEnabled: _isEnabled,
            labelBuilder: _dialogLabel,
            onCreateSubfoldersByDateChanged: (bool value) {
              setState(() {
                _createSubfoldersByDate = value;
              });
            },
            onEnabledChanged: (bool value) {
              setState(() {
                _isEnabled = value;
              });
            },
          ),
        ],
      ),
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
    return NextcloudDestinationFields(
      serverUrlController: _nextcloudServerUrlController,
      usernameController: _nextcloudUsernameController,
      appPasswordController: _nextcloudAppPasswordController,
      remotePathController: _nextcloudRemotePathController,
      folderNameController: _nextcloudFolderNameController,
      authMode: _nextcloudAuthMode,
      allowInvalidCertificates: _nextcloudAllowInvalidCertificates,
      isTestingConnection: _isTestingNextcloudConnection,
      labelBuilder: _dialogLabel,
      onAuthModeChanged: (NextcloudAuthMode value) {
        setState(() {
          _nextcloudAuthMode = value;
        });
      },
      onAllowInvalidCertificatesChanged: _setNextcloudAllowInvalidCertificates,
      onTestConnection: _testNextcloudConnection,
    );
  }

  Future<void> _setNextcloudAllowInvalidCertificates(bool value) async {
    if (!value) {
      setState(() => _nextcloudAllowInvalidCertificates = false);
      return;
    }

    final confirmed = await MessageModal.showConfirm(
      context,
      title: _dialogLabel('Atenção', 'Attention'),
      message: _dialogLabel(
        'Permitir certificado inválido reduz a segurança da conexão.\nHabilite apenas se o servidor usa certificado self-signed ou CA interna.',
        'Allowing invalid certificate reduces connection security.\nEnable only if server uses self-signed cert or internal CA.',
      ),
      confirmLabel: _dialogLabel('Habilitar', 'Enable'),
    );

    if (confirmed && mounted) {
      setState(() => _nextcloudAllowInvalidCertificates = true);
    }
  }

  Widget _buildFtpsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledToggle(
          title: _dialogLabel('Usar FTPS', 'Use FTPS'),
          description: _dialogLabel(
            'Conexão FTP segura (SSL/TLS)',
            'Secure FTP connection (SSL/TLS)',
          ),
          value: _useFtps,
          onChanged: (bool value) {
            setState(() {
              _useFtps = value;
            });
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (_useFtps) ...[
          LabeledToggle(
            title: _dialogLabel(
              'Permitir certificado FTPS invalido',
              'Allow invalid FTPS certificate',
            ),
            description: _dialogLabel(
              'Compatibilidade com certificados autoassinados. Desative para validar certificados em producao.',
              'Compatibility with self-signed certificates. Turn off to validate production certificates.',
            ),
            value: _ftpAllowInvalidCertificates,
            onChanged: (bool value) {
              setState(() {
                _ftpAllowInvalidCertificates = value;
              });
            },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        LabeledToggle(
          title: _dialogLabel(
            'Retomada de upload (REST STREAM)',
            'Upload resume (REST STREAM)',
          ),
          description: _dialogLabel(
            'Retomar envio do ponto de interrupção quando o servidor suportar',
            'Resume upload from interruption point when server supports it',
          ),
          value: _enableResumeFtp,
          onChanged: (bool value) {
            setState(() {
              _enableResumeFtp = value;
            });
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: _dialogLabel('Testar conexão FTP', 'Test FTP connection'),
          icon: FluentIcons.network_tower,
          onPressed: _testFtpConnection,
          isLoading: _isTestingFtpConnection,
        ),
        const SizedBox(height: AppSpacing.md),
        _buildFtpAdvancedOptions(),
      ],
    );
  }

  void _applyFtpIntegrityPreset(FtpIntegrityPreset preset) {
    _enableStrongIntegrityValidationFtp =
        preset.enablesStrongIntegrityValidation;
    _enableReadBackValidationFtp = preset.enablesReadBackValidation;
  }

  Widget _buildFtpAdvancedOptions() {
    return FtpAdvancedOptionsSection(
      integrityPreset: _ftpIntegrityPreset,
      whenResumeNotSupported: _whenResumeNotSupportedFtp,
      enableStrongIntegrityValidation: _enableStrongIntegrityValidationFtp,
      enableReadBackValidation: _enableReadBackValidationFtp,
      keepPartOnCancel: _keepPartOnCancelFtp,
      enableVerboseLog: _enableVerboseLogFtp,
      maxAttemptsController: _maxAttemptsFtpController,
      connectionTimeoutSecondsController: _connectionTimeoutSecondsController,
      uploadTimeoutMinutesController: _uploadTimeoutMinutesController,
      impactColor: _ftpIntegrityPreset.impactColor(context),
      impactText: _ftpIntegrityPreset.impactText(_dialogLabel),
      labelBuilder: _dialogLabel,
      onPresetChanged: (FtpIntegrityPreset value) {
        setState(() {
          _ftpIntegrityPreset = value;
          _applyFtpIntegrityPreset(value);
        });
      },
      onEnableStrongIntegrityValidationChanged: (bool value) {
        setState(() {
          _enableStrongIntegrityValidationFtp = value;
          if (!value) {
            _enableReadBackValidationFtp = false;
          }
          _ftpIntegrityPreset = FtpIntegrityPresetX.fromFlags(
            enableStrongIntegrityValidation:
                _enableStrongIntegrityValidationFtp,
            enableReadBackValidation: _enableReadBackValidationFtp,
          );
        });
      },
      onEnableReadBackValidationChanged: _enableStrongIntegrityValidationFtp
          ? (bool value) {
              setState(() {
                _enableReadBackValidationFtp = value;
                _ftpIntegrityPreset = FtpIntegrityPresetX.fromFlags(
                  enableStrongIntegrityValidation:
                      _enableStrongIntegrityValidationFtp,
                  enableReadBackValidation: _enableReadBackValidationFtp,
                );
              });
            }
          : null,
      onKeepPartOnCancelChanged: (bool value) {
        setState(() {
          _keepPartOnCancelFtp = value;
        });
      },
      onWhenResumeNotSupportedChanged: (FtpWhenResumeNotSupported value) {
        setState(() {
          _whenResumeNotSupportedFtp = value;
        });
      },
      onEnableVerboseLogChanged: (bool value) {
        setState(() {
          _enableVerboseLogFtp = value;
        });
      },
    );
  }

  List<Widget> _buildActions() {
    return [
      const CancelButton(),
      SaveButton(onPressed: _save, isEditing: isEditing),
    ];
  }

  Widget _buildLocalFields() {
    return LocalDestinationFields(
      pathController: _localPathController,
      labelBuilder: _dialogLabel,
      onSelectFolder: _selectLocalFolder,
    );
  }

  Widget _buildFtpFields() {
    return FtpConnectionFields(
      hostController: _ftpHostController,
      portController: _ftpPortController,
      usernameController: _ftpUsernameController,
      passwordController: _ftpPasswordController,
      remotePathController: _ftpRemotePathController,
      labelBuilder: _dialogLabel,
    );
  }

  Widget _buildGoogleDriveFields() {
    final googleAuth = getIt<GoogleAuthProvider>();

    return ListenableBuilder(
      listenable: googleAuth,
      builder: (BuildContext context, _) {
        final features = getIt<FeatureAvailabilityService>();
        return GoogleDriveDestinationFields(
          oauthAvailabilityWarning: !features.isExternalBrowserOAuthEnabled
              ? AppCallout(
                  tone: AppCalloutTone.warning,
                  message:
                      '${_dialogLabel('Inicio de sessao OAuth', 'OAuth sign-in')}. '
                      '${localizeCompatibilityReason(
                        context,
                        reason: features.externalBrowserOAuthDisabledReason,
                        fallbackPt: 'Não disponível nesta versão do Windows.',
                        fallbackEn: 'Not available on this Windows version.',
                      )}',
                )
              : null,
          authStatus: _buildGoogleAuthStatus(googleAuth),
          oauthConfigSection: !googleAuth.isConfigured
              ? _buildOAuthConfigSection(googleAuth)
              : null,
          folderField: _buildGoogleFolderField(googleAuth),
          notSignedInWarning: !googleAuth.isSignedIn
              ? _buildGoogleNotSignedInWarning()
              : null,
        );
      },
    );
  }

  Widget _buildGoogleFolderField(GoogleAuthProvider googleAuth) {
    return AppTextField(
      controller: _googleFolderNameController,
      label: _dialogLabel(
        'Nome da pasta no Google Drive',
        'Google Drive folder name',
      ),
      hint: 'Backups',
      prefixIcon: const Icon(FluentIcons.cloud),
      enabled: googleAuth.isSignedIn,
      validator: (String? value) {
        if (value == null || value.trim().isEmpty) {
          return _dialogLabel(
            'Nome da pasta é obrigatório',
            'Folder name is required',
          );
        }
        return null;
      },
    );
  }

  Widget _buildGoogleNotSignedInWarning() {
    return AppCallout(
      tone: AppCalloutTone.danger,
      message: _dialogLabel(
        'Conecte-se ao Google para configurar o destino.',
        'Sign in to Google to configure this destination.',
      ),
    );
  }

  Widget _buildGoogleAuthStatus(GoogleAuthProvider googleAuth) {
    final features = getIt<FeatureAvailabilityService>();
    final oauthOk = features.isExternalBrowserOAuthEnabled;
    final isSignedIn = googleAuth.isSignedIn;
    final isLoading = googleAuth.isLoading;

    return OAuthStatusCard(
      isSignedIn: isSignedIn,
      isLoading: isLoading,
      isConfigured: googleAuth.isConfigured,
      signedInBackgroundColor: AppPalette.googleDriveSignedInBackground,
      signedInBorderColor: AppPalette.googleDriveSignedInBorder,
      signedInIconColor: AppPalette.googleDriveSignedIn,
      signedInLabel: _dialogLabel(
        'Conectado como ${googleAuth.currentEmail ?? 'usuario'}',
        'Connected as ${googleAuth.currentEmail ?? 'user'}',
      ),
      signedOutLabel: _dialogLabel(
        'Não conectado ao Google',
        'Not connected to Google',
      ),
      disconnectLabel: _dialogLabel('Desconectar', 'Disconnect'),
      connectLabel: _dialogLabel('Conectar ao Google', 'Connect to Google'),
      connectingLabel: _dialogLabel('Conectando...', 'Connecting...'),
      errorMessage: googleAuth.error,
      onDisconnect: () => googleAuth.signOut(),
      onConnect: (!oauthOk || isLoading)
          ? null
          : () => _connectToGoogle(googleAuth),
    );
  }

  Widget _buildOAuthConfigSection(GoogleAuthProvider googleAuth) {
    return OAuthCredentialsSectionCard(
      title: _dialogLabel('Configuracao OAuth', 'OAuth configuration'),
      description: _dialogLabel(
        'Para usar o Google Drive, configure as credenciais OAuth do Google Cloud Console.',
        'To use Google Drive, configure OAuth credentials in Google Cloud Console.',
      ),
      actionLabel: _dialogLabel(
        'Configurar credenciais',
        'Configure credentials',
      ),
      onPressed: () => _showOAuthConfigDialog(googleAuth),
    );
  }

  Future<void> _connectToGoogle(GoogleAuthProvider googleAuth) async {
    if (!getIt<FeatureAvailabilityService>().isExternalBrowserOAuthEnabled) {
      return;
    }
    final success = await googleAuth.signIn();
    if (success && mounted) {
      _showSuccess(
        _dialogLabel(
          'Conectado ao Google com sucesso!',
          'Connected to Google successfully!',
        ),
      );
    }
  }

  Future<void> _showOAuthConfigDialog(GoogleAuthProvider googleAuth) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => OAuthConfigDialog(
        googleAuth: googleAuth,
        initialClientId: googleAuth.oauthConfig?.clientId ?? '',
        initialClientSecret: googleAuth.oauthConfig?.clientSecret ?? '',
      ),
    );

    if ((result ?? false) && mounted) {
      _showSuccess(
        _dialogLabel(
          'Credenciais OAuth configuradas!',
          'OAuth credentials configured!',
        ),
      );
    }
  }

  Widget _buildDropboxFields() {
    final dropboxAuth = getIt<DropboxAuthProvider>();

    return ListenableBuilder(
      listenable: dropboxAuth,
      builder: (BuildContext context, _) {
        final features = getIt<FeatureAvailabilityService>();
        return DropboxDestinationFields(
          oauthAvailabilityWarning: !features.isExternalBrowserOAuthEnabled
              ? AppCallout(
                  tone: AppCalloutTone.warning,
                  message:
                      '${_dialogLabel('Inicio de sessao OAuth', 'OAuth sign-in')}. '
                      '${localizeCompatibilityReason(
                        context,
                        reason: features.externalBrowserOAuthDisabledReason,
                        fallbackPt: 'Não disponível nesta versão do Windows.',
                        fallbackEn: 'Not available on this Windows version.',
                      )}',
                )
              : null,
          authStatus: _buildDropboxAuthStatus(dropboxAuth),
          oauthConfigSection: !dropboxAuth.isSignedIn
              ? _buildDropboxOAuthConfigSection(dropboxAuth)
              : null,
          folderFields: _buildDropboxFolderFields(dropboxAuth),
          notSignedInWarning: !dropboxAuth.isSignedIn
              ? _buildDropboxNotSignedInWarning()
              : null,
        );
      },
    );
  }

  Widget _buildDropboxFolderFields(DropboxAuthProvider dropboxAuth) {
    return Column(
      children: [
        AppTextField(
          controller: _dropboxFolderPathController,
          label: _dialogLabel(
            'Caminho da pasta (opcional)',
            'Folder path (optional)',
          ),
          hint: _dialogLabel(
            '/Backups ou deixe vazio para raiz',
            '/Backups or leave empty for root',
          ),
          prefixIcon: const Icon(FluentIcons.folder),
          enabled: dropboxAuth.isSignedIn,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _dropboxFolderNameController,
          label: _dialogLabel(
            'Nome da pasta no Dropbox',
            'Dropbox folder name',
          ),
          hint: 'Backups',
          prefixIcon: const Icon(FluentIcons.cloud),
          enabled: dropboxAuth.isSignedIn,
          validator: (String? value) {
            if (value == null || value.trim().isEmpty) {
              return _dialogLabel(
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
    return AppCallout(
      tone: AppCalloutTone.danger,
      message: _dialogLabel(
        'Conecte-se ao Dropbox para configurar o destino.',
        'Sign in to Dropbox to configure this destination.',
      ),
    );
  }

  Widget _buildDropboxAuthStatus(DropboxAuthProvider dropboxAuth) {
    final features = getIt<FeatureAvailabilityService>();
    final oauthOk = features.isExternalBrowserOAuthEnabled;
    final isSignedIn = dropboxAuth.isSignedIn;
    final isLoading = dropboxAuth.isLoading;

    return OAuthStatusCard(
      isSignedIn: isSignedIn,
      isLoading: isLoading,
      isConfigured: dropboxAuth.isConfigured,
      signedInBackgroundColor: AppPalette.destinationDropbox.withValues(
        alpha: 0.1,
      ),
      signedInBorderColor: AppPalette.destinationDropbox.withValues(
        alpha: 0.3,
      ),
      signedInIconColor: AppPalette.destinationDropbox,
      signedInLabel: _dialogLabel(
        'Conectado como ${dropboxAuth.currentEmail ?? 'usuario'}',
        'Connected as ${dropboxAuth.currentEmail ?? 'user'}',
      ),
      signedOutLabel: _dialogLabel(
        'Não conectado ao Dropbox',
        'Not connected to Dropbox',
      ),
      disconnectLabel: _dialogLabel('Desconectar', 'Disconnect'),
      connectLabel: _dialogLabel('Conectar ao Dropbox', 'Connect to Dropbox'),
      connectingLabel: _dialogLabel('Conectando...', 'Connecting...'),
      errorMessage: dropboxAuth.error,
      onDisconnect: () => dropboxAuth.signOut(),
      onConnect: (!oauthOk || isLoading)
          ? null
          : () => _connectToDropbox(dropboxAuth),
    );
  }

  Widget _buildDropboxOAuthConfigSection(DropboxAuthProvider dropboxAuth) {
    final isConfigured = dropboxAuth.isConfigured;
    final hasClientId = dropboxAuth.oauthConfig?.clientId.isNotEmpty ?? false;

    return OAuthCredentialsSectionCard(
      title: _dialogLabel('Configuracao OAuth', 'OAuth configuration'),
      description: isConfigured && hasClientId
          ? _dialogLabel(
              'Credenciais OAuth configuradas. Clique em "Alterar credenciais" para modificar.',
              'OAuth credentials configured. Click "Change credentials" to modify.',
            )
          : _dialogLabel(
              'Para usar o Dropbox, configure as credenciais OAuth do Dropbox App Console.',
              'To use Dropbox, configure OAuth credentials in Dropbox App Console.',
            ),
      actionLabel: isConfigured && hasClientId
          ? _dialogLabel('Alterar credenciais', 'Change credentials')
          : _dialogLabel('Configurar credenciais', 'Configure credentials'),
      onPressed: () => _showDropboxOAuthConfigDialog(dropboxAuth),
    );
  }

  Future<void> _connectToDropbox(DropboxAuthProvider dropboxAuth) async {
    if (!getIt<FeatureAvailabilityService>().isExternalBrowserOAuthEnabled) {
      return;
    }
    final success = await dropboxAuth.signIn();
    if (success && mounted) {
      _showSuccess(
        _dialogLabel(
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
      builder: (BuildContext dialogContext) => DropboxOAuthConfigDialog(
        dropboxAuth: dropboxAuth,
        initialClientId: dropboxAuth.oauthConfig?.clientId ?? '',
        initialClientSecret: dropboxAuth.oauthConfig?.clientSecret ?? '',
      ),
    );

    if ((result ?? false) && mounted) {
      _showSuccess(
        _dialogLabel(
          'Credenciais OAuth configuradas!',
          'OAuth credentials configured!',
        ),
      );
    }
  }

  Future<void> _selectLocalFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: _dialogLabel(
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
      _showError(
        _dialogLabel('Servidor FTP é obrigatório', 'FTP server is required'),
      );
      return;
    }
    if (_ftpPortController.text.trim().isEmpty) {
      _showError(_dialogLabel('Porta é obrigatória', 'Port is required'));
      return;
    }
    if (_ftpUsernameController.text.trim().isEmpty) {
      _showError(_dialogLabel('Usuário é obrigatório', 'Username is required'));
      return;
    }
    if (_ftpPasswordController.text.trim().isEmpty) {
      _showError(_dialogLabel('Senha é obrigatória', 'Password is required'));
      return;
    }

    setState(() {
      _isTestingFtpConnection = true;
    });

    try {
      final port = int.tryParse(_ftpPortController.text.trim());
      if (port == null || port < 1 || port > 65535) {
        _showError(
          _dialogLabel(
            'Porta inválida. Use um valor entre 1 e 65535',
            'Invalid port. Use a value between 1 and 65535',
          ),
        );
        return;
      }

      final connTimeoutStr = _connectionTimeoutSecondsController.text.trim();
      final connTimeout = connTimeoutStr.isEmpty
          ? null
          : int.tryParse(connTimeoutStr);
      final uploadTimeoutStr = _uploadTimeoutMinutesController.text.trim();
      final uploadTimeout = uploadTimeoutStr.isEmpty
          ? null
          : int.tryParse(uploadTimeoutStr);

      final config = FtpDestinationConfig.fromJson({
        'host': _ftpHostController.text.trim(),
        'port': port,
        'username': _ftpUsernameController.text.trim(),
        'password': _ftpPasswordController.text,
        'remotePath': _ftpRemotePathController.text.trim(),
        'useFtps': _useFtps,
        'allowInvalidCertificates': _ftpAllowInvalidCertificates,
        'enableVerboseLog': _enableVerboseLogFtp,
        'enableStrongIntegrityValidation': _enableStrongIntegrityValidationFtp,
        'enableReadBackValidation': _enableReadBackValidationFtp,
        'connectionTimeoutSeconds': connTimeout,
        'uploadTimeoutMinutes': uploadTimeout,
      });

      final ftpService = getIt<IFtpService>();
      final result = await ftpService.testConnection(config);

      if (!mounted) return;

      result.fold(
        (testResult) {
          if (testResult.ok) {
            final restInfo = switch (testResult.supportsRestStream) {
              true =>
                '\n${_dialogLabel("Suporta retomada de upload (REST STREAM).", "Supports upload resume (REST STREAM).")}',
              false =>
                '\n${_dialogLabel(
                  "Não suporta retomada de upload. "
                      "Em caso de interrupção, o envio será reiniciado do zero.",
                  "Does not support upload resume. "
                      "If interrupted, upload will restart from the beginning.",
                )}',
              null => '',
            };
            final compatWarnings = <String>[];
            if (testResult.canWrite == false) {
              compatWarnings.add(
                _dialogLabel(
                  'Sem permissão de escrita no diretório remoto.',
                  'No write permission on remote directory.',
                ),
              );
            }
            if (testResult.canRename == false) {
              compatWarnings.add(
                _dialogLabel(
                  'Renomear arquivos não permitido (RNFR/RNTO). '
                      'Upload pode falhar na publicação final.',
                  'File rename not allowed (RNFR/RNTO). '
                      'Upload may fail at final publication.',
                ),
              );
            }
            final warningInfo = compatWarnings.isEmpty
                ? ''
                : '\n${_dialogLabel("Avisos:", "Warnings:")} ${compatWarnings.join(" ")}'
                      '${compatWarnings.isNotEmpty ? " " : ""}'
                      '${_dialogLabel("Consulte o guia de configuração do servidor FTP.", "See FTP server configuration guide.")}';
            _showSuccess(
              _dialogLabel(
                'Conexão FTP estabelecida com sucesso!$restInfo$warningInfo',
                'FTP connection established successfully!$restInfo$warningInfo',
              ),
            );
          } else {
            _showError(
              _dialogLabel(
                'Falha ao conectar ao servidor FTP',
                'Failed to connect to FTP server',
              ),
            );
          }
        },
        (failure) {
          final message = failureUserMessage(
            failure,
            fallback: _dialogLabel('Erro desconhecido', 'Unknown error'),
          );
          _showError(
            _dialogLabel(
              'Erro ao testar conexão FTP:\n$message',
              'Error testing FTP connection:\n$message',
            ),
          );
        },
      );
    } on Object catch (e) {
      if (mounted) {
        _showError(_dialogLabel('Erro inesperado: $e', 'Unexpected error: $e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingFtpConnection = false;
        });
      }
    }
  }

  Future<void> _testNextcloudConnection() async {
    if (_nextcloudServerUrlController.text.trim().isEmpty) {
      _showError(
        _dialogLabel(
          'URL do Nextcloud é obrigatória',
          'Nextcloud URL is required',
        ),
      );
      return;
    }
    if (_nextcloudUsernameController.text.trim().isEmpty) {
      _showError(_dialogLabel('Usuário é obrigatório', 'Username is required'));
      return;
    }
    if (_nextcloudAppPasswordController.text.trim().isEmpty) {
      _showError(
        _nextcloudAuthMode == NextcloudAuthMode.appPassword
            ? _dialogLabel(
                'App Password é obrigatório',
                'App Password is required',
              )
            : _dialogLabel(
                'Senha do usuário é obrigatória',
                'User password is required',
              ),
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

      final nextcloudService = getIt<INextcloudDestinationService>();
      final result = await nextcloudService.testConnection(config);

      if (!mounted) return;

      result.fold(
        (success) {
          if (success) {
            _showSuccess(
              _dialogLabel(
                'Conexão Nextcloud estabelecida com sucesso!',
                'Nextcloud connection established successfully!',
              ),
            );
          } else {
            _showError(
              _dialogLabel(
                'Falha ao conectar ao servidor Nextcloud',
                'Failed to connect to Nextcloud server',
              ),
            );
          }
        },
        (failure) {
          final message = failureUserMessage(
            failure,
            fallback: _dialogLabel('Erro desconhecido', 'Unknown error'),
          );
          _showError(
            _dialogLabel(
              'Erro ao testar conexão Nextcloud:\n$message',
              'Error testing Nextcloud connection:\n$message',
            ),
          );
        },
      );
    } on Object catch (e) {
      if (mounted) {
        _showError(_dialogLabel('Erro inesperado: $e', 'Unexpected error: $e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingNextcloudConnection = false;
        });
      }
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    unawaited(FluentInfoBarFeedback.showSuccess(context, message: message));
  }

  void _showError(String message) {
    if (!mounted) return;
    unawaited(MessageModal.showError(context, message: message));
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
          _dialogLabel(
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
          _dialogLabel(
            'Conecte-se ao Dropbox antes de salvar.',
            'Connect to Dropbox before saving.',
          ),
        );
        return;
      }
    }

    if (_selectedType == DestinationType.nextcloud) {
      final licenseProvider = context.read<LicenseProvider>();
      final hasNextcloud = licenseProvider.isFeatureUnlocked(
        LicenseFeatures.nextcloud,
      );
      if (!hasNextcloud) {
        _showError(
          _dialogLabel(
            'Este destino requer uma licença válida. Acesse Configurações > Licenciamento.',
            'This destination requires a valid license. Go to Settings > Licensing.',
          ),
        );
        return;
      }
    }

    final retentionDays = int.parse(_retentionDaysController.text);
    late final String configJson;

    switch (_selectedType) {
      case DestinationType.local:
        configJson = jsonEncode({
          'path': _localPathController.text.trim(),
          'createSubfoldersByDate': _createSubfoldersByDate,
          'retentionDays': retentionDays,
        });
      case DestinationType.ftp:
        final connTimeoutStr = _connectionTimeoutSecondsController.text.trim();
        final connTimeout = connTimeoutStr.isEmpty
            ? null
            : int.tryParse(connTimeoutStr);
        final uploadTimeoutStr = _uploadTimeoutMinutesController.text.trim();
        final uploadTimeout = uploadTimeoutStr.isEmpty
            ? null
            : int.tryParse(uploadTimeoutStr);
        final maxAttemptsStr = _maxAttemptsFtpController.text.trim();
        final maxAttempts = maxAttemptsStr.isEmpty
            ? null
            : int.tryParse(maxAttemptsStr);
        configJson = jsonEncode({
          'host': _ftpHostController.text.trim(),
          'port': int.parse(_ftpPortController.text),
          'username': _ftpUsernameController.text.trim(),
          'password': _ftpPasswordController.text,
          'remotePath': _ftpRemotePathController.text.trim(),
          'useFtps': _useFtps,
          'allowInvalidCertificates': _ftpAllowInvalidCertificates,
          'enableResume': _enableResumeFtp,
          'keepPartOnCancel': _keepPartOnCancelFtp,
          'whenResumeNotSupported': _whenResumeNotSupportedFtp.name,
          ...?(maxAttempts != null ? {'maxAttempts': maxAttempts} : null),
          'enableVerboseLog': _enableVerboseLogFtp,
          'enableStrongIntegrityValidation':
              _enableStrongIntegrityValidationFtp,
          'enableReadBackValidation': _enableReadBackValidationFtp,
          ...?(connTimeout != null
              ? {'connectionTimeoutSeconds': connTimeout}
              : null),
          ...?(uploadTimeout != null
              ? {'uploadTimeoutMinutes': uploadTimeout}
              : null),
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
