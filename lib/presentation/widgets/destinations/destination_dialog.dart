import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/providers/dropbox_auth_provider.dart';
import 'package:backup_database/application/providers/google_auth_provider.dart';
import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_connection_testers.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_draft.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_dropbox_oauth_dialog.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_dropbox_oauth_slots.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_ftp_advanced.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_ftp_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_ftps_section.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_google_oauth_dialog.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_google_oauth_slots.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_local_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_nextcloud_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_shell.dart';
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
      constraints: AppDialogConstraints.of(
        context,
        preferredWidth: 600,
      ),
      title: DestinationDialogTitle(
        selectedType: _selectedType,
        isEditing: isEditing,
        labelBuilder: _dialogLabel,
      ),
      content: DestinationDialogContent(
        formKey: _formKey,
        selectedType: _selectedType,
        isEditing: isEditing,
        nameController: _nameController,
        labelBuilder: _dialogLabel,
        onTypeChanged: (DestinationType value) {
          setState(() {
            _selectedType = value;
          });
        },
        typeSpecificFields: _DestinationTypeSpecificFields(
          selectedType: _selectedType,
          localPathController: _localPathController,
          onSelectLocalFolder: _selectLocalFolder,
          ftpHostController: _ftpHostController,
          ftpPortController: _ftpPortController,
          ftpUsernameController: _ftpUsernameController,
          ftpPasswordController: _ftpPasswordController,
          ftpRemotePathController: _ftpRemotePathController,
          googleFolderNameController: _googleFolderNameController,
          onGoogleConnect: _connectToGoogle,
          onGoogleConfigureCredentials: _showOAuthConfigDialog,
          dropboxFolderPathController: _dropboxFolderPathController,
          dropboxFolderNameController: _dropboxFolderNameController,
          onDropboxConnect: _connectToDropbox,
          onDropboxConfigureCredentials: _showDropboxOAuthConfigDialog,
          nextcloudServerUrlController: _nextcloudServerUrlController,
          nextcloudUsernameController: _nextcloudUsernameController,
          nextcloudAppPasswordController: _nextcloudAppPasswordController,
          nextcloudRemotePathController: _nextcloudRemotePathController,
          nextcloudFolderNameController: _nextcloudFolderNameController,
          nextcloudAuthMode: _nextcloudAuthMode,
          nextcloudAllowInvalidCertificates: _nextcloudAllowInvalidCertificates,
          isTestingNextcloudConnection: _isTestingNextcloudConnection,
          onNextcloudAuthModeChanged: (NextcloudAuthMode value) {
            setState(() {
              _nextcloudAuthMode = value;
            });
          },
          onNextcloudAllowInvalidCertificatesChanged:
              _setNextcloudAllowInvalidCertificates,
          onTestNextcloudConnection: _testNextcloudConnection,
          labelBuilder: _dialogLabel,
        ),
        ftpExtraSection: _selectedType == DestinationType.ftp
            ? FtpSecurityAndResumeSection(
                useFtps: _useFtps,
                allowInvalidCertificates: _ftpAllowInvalidCertificates,
                enableResume: _enableResumeFtp,
                isTestingConnection: _isTestingFtpConnection,
                labelBuilder: _dialogLabel,
                onUseFtpsChanged: (bool value) {
                  setState(() {
                    _useFtps = value;
                  });
                },
                onAllowInvalidCertificatesChanged: (bool value) {
                  setState(() {
                    _ftpAllowInvalidCertificates = value;
                  });
                },
                onEnableResumeChanged: (bool value) {
                  setState(() {
                    _enableResumeFtp = value;
                  });
                },
                onTestConnection: _testFtpConnection,
                advancedOptions: FtpAdvancedOptionsSlot(
                  integrityPreset: _ftpIntegrityPreset,
                  whenResumeNotSupported: _whenResumeNotSupportedFtp,
                  enableStrongIntegrityValidation:
                      _enableStrongIntegrityValidationFtp,
                  enableReadBackValidation: _enableReadBackValidationFtp,
                  keepPartOnCancel: _keepPartOnCancelFtp,
                  enableVerboseLog: _enableVerboseLogFtp,
                  maxAttemptsController: _maxAttemptsFtpController,
                  connectionTimeoutSecondsController:
                      _connectionTimeoutSecondsController,
                  uploadTimeoutMinutesController:
                      _uploadTimeoutMinutesController,
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
                  onEnableReadBackValidationChanged:
                      _enableStrongIntegrityValidationFtp
                      ? (bool value) {
                          setState(() {
                            _enableReadBackValidationFtp = value;
                            _ftpIntegrityPreset = FtpIntegrityPresetX.fromFlags(
                              enableStrongIntegrityValidation:
                                  _enableStrongIntegrityValidationFtp,
                              enableReadBackValidation:
                                  _enableReadBackValidationFtp,
                            );
                          });
                        }
                      : null,
                  onKeepPartOnCancelChanged: (bool value) {
                    setState(() {
                      _keepPartOnCancelFtp = value;
                    });
                  },
                  onWhenResumeNotSupportedChanged:
                      (FtpWhenResumeNotSupported value) {
                        setState(() {
                          _whenResumeNotSupportedFtp = value;
                        });
                      },
                  onEnableVerboseLogChanged: (bool value) {
                    setState(() {
                      _enableVerboseLogFtp = value;
                    });
                  },
                ),
              )
            : null,
        retentionDaysController: _retentionDaysController,
        createSubfoldersByDate: _createSubfoldersByDate,
        isEnabled: _isEnabled,
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
      actions: [
        const CancelButton(),
        SaveButton(onPressed: _save, isEditing: isEditing),
      ],
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

  void _applyFtpIntegrityPreset(FtpIntegrityPreset preset) {
    _enableStrongIntegrityValidationFtp =
        preset.enablesStrongIntegrityValidation;
    _enableReadBackValidationFtp = preset.enablesReadBackValidation;
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

  DestinationDialogConnectionTesters _connectionTesters() {
    return DestinationDialogConnectionTesters(
      ftpService: getIt<IFtpService>(),
      nextcloudService: getIt<INextcloudDestinationService>(),
      label: _dialogLabel,
    );
  }

  Future<void> _testFtpConnection() async {
    var probeStarted = false;
    try {
      final feedback = await _connectionTesters().testFtpConnection(
        hostController: _ftpHostController,
        portController: _ftpPortController,
        usernameController: _ftpUsernameController,
        passwordController: _ftpPasswordController,
        remotePathController: _ftpRemotePathController,
        connectionTimeoutSecondsController: _connectionTimeoutSecondsController,
        uploadTimeoutMinutesController: _uploadTimeoutMinutesController,
        useFtps: _useFtps,
        allowInvalidCertificates: _ftpAllowInvalidCertificates,
        enableVerboseLog: _enableVerboseLogFtp,
        enableStrongIntegrityValidation: _enableStrongIntegrityValidationFtp,
        enableReadBackValidation: _enableReadBackValidationFtp,
        onProbeStarted: () {
          probeStarted = true;
          setState(() {
            _isTestingFtpConnection = true;
          });
        },
      );
      if (!mounted) {
        return;
      }
      _applyConnectionTestFeedback(feedback);
    } on Object catch (e) {
      if (mounted) {
        _showError(_dialogLabel('Erro inesperado: $e', 'Unexpected error: $e'));
      }
    } finally {
      if (probeStarted && mounted) {
        setState(() {
          _isTestingFtpConnection = false;
        });
      }
    }
  }

  Future<void> _testNextcloudConnection() async {
    var probeStarted = false;
    try {
      final feedback = await _connectionTesters().testNextcloudConnection(
        serverUrlController: _nextcloudServerUrlController,
        usernameController: _nextcloudUsernameController,
        appPasswordController: _nextcloudAppPasswordController,
        remotePathController: _nextcloudRemotePathController,
        folderNameController: _nextcloudFolderNameController,
        authMode: _nextcloudAuthMode,
        allowInvalidCertificates: _nextcloudAllowInvalidCertificates,
        onProbeStarted: () {
          probeStarted = true;
          setState(() {
            _isTestingNextcloudConnection = true;
          });
        },
      );
      if (!mounted) {
        return;
      }
      _applyConnectionTestFeedback(feedback);
    } on Object catch (e) {
      if (mounted) {
        _showError(_dialogLabel('Erro inesperado: $e', 'Unexpected error: $e'));
      }
    } finally {
      if (probeStarted && mounted) {
        setState(() {
          _isTestingNextcloudConnection = false;
        });
      }
    }
  }

  void _applyConnectionTestFeedback(
    DestinationConnectionTestFeedback feedback,
  ) {
    switch (feedback) {
      case DestinationConnectionTestSucceeded(:final message):
        _showSuccess(message);
      case DestinationConnectionTestFailed(:final message):
        _showError(message);
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

    final draft = DestinationDialogDraft(
      id: widget.destination?.id,
      name: _nameController.text.trim(),
      type: _selectedType,
      enabled: _isEnabled,
      createdAt: widget.destination?.createdAt,
      retentionDays: int.parse(_retentionDaysController.text),
      localPath: _localPathController.text.trim(),
      createSubfoldersByDate: _createSubfoldersByDate,
      ftpHost: _ftpHostController.text.trim(),
      ftpPortText: _ftpPortController.text,
      ftpUsername: _ftpUsernameController.text.trim(),
      ftpPassword: _ftpPasswordController.text,
      ftpRemotePath: _ftpRemotePathController.text.trim(),
      useFtps: _useFtps,
      ftpAllowInvalidCertificates: _ftpAllowInvalidCertificates,
      enableResumeFtp: _enableResumeFtp,
      keepPartOnCancelFtp: _keepPartOnCancelFtp,
      whenResumeNotSupportedFtp: _whenResumeNotSupportedFtp,
      ftpMaxAttemptsText: _maxAttemptsFtpController.text,
      enableVerboseLogFtp: _enableVerboseLogFtp,
      enableStrongIntegrityValidationFtp: _enableStrongIntegrityValidationFtp,
      enableReadBackValidationFtp: _enableReadBackValidationFtp,
      ftpConnectionTimeoutSecondsText: _connectionTimeoutSecondsController.text,
      ftpUploadTimeoutMinutesText: _uploadTimeoutMinutesController.text,
      googleFolderName: _googleFolderNameController.text.trim(),
      dropboxFolderPath: _dropboxFolderPathController.text.trim(),
      dropboxFolderName: _dropboxFolderNameController.text.trim(),
      nextcloudServerUrl: _nextcloudServerUrlController.text.trim(),
      nextcloudUsername: _nextcloudUsernameController.text.trim(),
      nextcloudAppPassword: EncryptionService.encrypt(
        _nextcloudAppPasswordController.text,
      ),
      nextcloudAuthMode: _nextcloudAuthMode,
      nextcloudRemotePath: _nextcloudRemotePathController.text.trim(),
      nextcloudFolderName: _nextcloudFolderNameController.text.trim(),
      nextcloudAllowInvalidCertificates: _nextcloudAllowInvalidCertificates,
    );

    Navigator.of(context).pop(draft.toDestination());
  }
}

class _DestinationTypeSpecificFields extends StatelessWidget {
  const _DestinationTypeSpecificFields({
    required this.selectedType,
    required this.localPathController,
    required this.onSelectLocalFolder,
    required this.ftpHostController,
    required this.ftpPortController,
    required this.ftpUsernameController,
    required this.ftpPasswordController,
    required this.ftpRemotePathController,
    required this.googleFolderNameController,
    required this.onGoogleConnect,
    required this.onGoogleConfigureCredentials,
    required this.dropboxFolderPathController,
    required this.dropboxFolderNameController,
    required this.onDropboxConnect,
    required this.onDropboxConfigureCredentials,
    required this.nextcloudServerUrlController,
    required this.nextcloudUsernameController,
    required this.nextcloudAppPasswordController,
    required this.nextcloudRemotePathController,
    required this.nextcloudFolderNameController,
    required this.nextcloudAuthMode,
    required this.nextcloudAllowInvalidCertificates,
    required this.isTestingNextcloudConnection,
    required this.onNextcloudAuthModeChanged,
    required this.onNextcloudAllowInvalidCertificatesChanged,
    required this.onTestNextcloudConnection,
    required this.labelBuilder,
  });

  final DestinationType selectedType;
  final TextEditingController localPathController;
  final VoidCallback onSelectLocalFolder;
  final TextEditingController ftpHostController;
  final TextEditingController ftpPortController;
  final TextEditingController ftpUsernameController;
  final TextEditingController ftpPasswordController;
  final TextEditingController ftpRemotePathController;
  final TextEditingController googleFolderNameController;
  final Future<void> Function(GoogleAuthProvider auth) onGoogleConnect;
  final Future<void> Function(GoogleAuthProvider auth)
  onGoogleConfigureCredentials;
  final TextEditingController dropboxFolderPathController;
  final TextEditingController dropboxFolderNameController;
  final Future<void> Function(DropboxAuthProvider auth) onDropboxConnect;
  final Future<void> Function(DropboxAuthProvider auth)
  onDropboxConfigureCredentials;
  final TextEditingController nextcloudServerUrlController;
  final TextEditingController nextcloudUsernameController;
  final TextEditingController nextcloudAppPasswordController;
  final TextEditingController nextcloudRemotePathController;
  final TextEditingController nextcloudFolderNameController;
  final NextcloudAuthMode nextcloudAuthMode;
  final bool nextcloudAllowInvalidCertificates;
  final bool isTestingNextcloudConnection;
  final ValueChanged<NextcloudAuthMode> onNextcloudAuthModeChanged;
  final ValueChanged<bool> onNextcloudAllowInvalidCertificatesChanged;
  final VoidCallback onTestNextcloudConnection;
  final DestinationDialogLabelBuilder labelBuilder;

  @override
  Widget build(BuildContext context) {
    return switch (selectedType) {
      DestinationType.local => LocalDestinationFields(
        pathController: localPathController,
        labelBuilder: labelBuilder,
        onSelectFolder: onSelectLocalFolder,
      ),
      DestinationType.ftp => FtpConnectionFields(
        hostController: ftpHostController,
        portController: ftpPortController,
        usernameController: ftpUsernameController,
        passwordController: ftpPasswordController,
        remotePathController: ftpRemotePathController,
        labelBuilder: labelBuilder,
      ),
      DestinationType.googleDrive => GoogleDriveOAuthSlots(
        folderNameController: googleFolderNameController,
        labelBuilder: labelBuilder,
        onConnect: onGoogleConnect,
        onConfigureCredentials: onGoogleConfigureCredentials,
      ),
      DestinationType.dropbox => DropboxOAuthSlots(
        folderPathController: dropboxFolderPathController,
        folderNameController: dropboxFolderNameController,
        labelBuilder: labelBuilder,
        onConnect: onDropboxConnect,
        onConfigureCredentials: onDropboxConfigureCredentials,
      ),
      DestinationType.nextcloud => NextcloudDestinationFields(
        serverUrlController: nextcloudServerUrlController,
        usernameController: nextcloudUsernameController,
        appPasswordController: nextcloudAppPasswordController,
        remotePathController: nextcloudRemotePathController,
        folderNameController: nextcloudFolderNameController,
        authMode: nextcloudAuthMode,
        allowInvalidCertificates: nextcloudAllowInvalidCertificates,
        isTestingConnection: isTestingNextcloudConnection,
        labelBuilder: labelBuilder,
        onAuthModeChanged: onNextcloudAuthModeChanged,
        onAllowInvalidCertificatesChanged:
            onNextcloudAllowInvalidCertificatesChanged,
        onTestConnection: onTestNextcloudConnection,
      ),
    };
  }
}
