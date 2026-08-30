import 'package:backup_database/application/providers/google_auth_provider.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_google_drive_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_oauth_availability_warning.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_oauth_credentials_card.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_oauth_status_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — Google Drive OAuth status, credentials, folder and warnings.
class GoogleDriveOAuthSlots extends StatelessWidget {
  const GoogleDriveOAuthSlots({
    required this.folderNameController,
    required this.labelBuilder,
    required this.onConnect,
    required this.onConfigureCredentials,
    super.key,
  });

  final TextEditingController folderNameController;
  final DestinationDialogLabelBuilder labelBuilder;
  final Future<void> Function(GoogleAuthProvider auth) onConnect;
  final Future<void> Function(GoogleAuthProvider auth) onConfigureCredentials;

  @override
  Widget build(BuildContext context) {
    final googleAuth = getIt<GoogleAuthProvider>();

    return ListenableBuilder(
      listenable: googleAuth,
      builder: (BuildContext context, _) {
        return GoogleDriveDestinationFields(
          oauthAvailabilityWarning: OAuthAvailabilityWarning.maybeOf(
            context: context,
            labelBuilder: labelBuilder,
          ),
          authStatus: GoogleDriveAuthStatus(
            googleAuth: googleAuth,
            labelBuilder: labelBuilder,
            onConnect: () => onConnect(googleAuth),
          ),
          oauthConfigSection: !googleAuth.isConfigured
              ? GoogleDriveOAuthConfigSection(
                  labelBuilder: labelBuilder,
                  onPressed: () => onConfigureCredentials(googleAuth),
                )
              : null,
          folderField: GoogleDriveFolderField(
            controller: folderNameController,
            enabled: googleAuth.isSignedIn,
            labelBuilder: labelBuilder,
          ),
          notSignedInWarning: !googleAuth.isSignedIn
              ? GoogleDriveNotSignedInWarning(labelBuilder: labelBuilder)
              : null,
        );
      },
    );
  }
}

/// **Molecule** — Google Drive destination folder name.
class GoogleDriveFolderField extends StatelessWidget {
  const GoogleDriveFolderField({
    required this.controller,
    required this.enabled,
    required this.labelBuilder,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final DestinationDialogLabelBuilder labelBuilder;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: labelBuilder(
        'Nome da pasta no Google Drive',
        'Google Drive folder name',
      ),
      hint: 'Backups',
      prefixIcon: const Icon(FluentIcons.cloud),
      enabled: enabled,
      validator: (String? value) {
        if (value == null || value.trim().isEmpty) {
          return labelBuilder(
            'Nome da pasta é obrigatório',
            'Folder name is required',
          );
        }
        return null;
      },
    );
  }
}

/// **Atom** — prompt to sign in before configuring Google Drive.
class GoogleDriveNotSignedInWarning extends StatelessWidget {
  const GoogleDriveNotSignedInWarning({
    required this.labelBuilder,
    super.key,
  });

  final DestinationDialogLabelBuilder labelBuilder;

  @override
  Widget build(BuildContext context) {
    return AppCallout(
      tone: AppCalloutTone.danger,
      message: labelBuilder(
        'Conecte-se ao Google para configurar o destino.',
        'Sign in to Google to configure this destination.',
      ),
    );
  }
}

/// **Molecule** — Google OAuth signed-in/out status card.
class GoogleDriveAuthStatus extends StatelessWidget {
  const GoogleDriveAuthStatus({
    required this.googleAuth,
    required this.labelBuilder,
    required this.onConnect,
    super.key,
  });

  final GoogleAuthProvider googleAuth;
  final DestinationDialogLabelBuilder labelBuilder;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
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
      signedInLabel: labelBuilder(
        'Conectado como ${googleAuth.currentEmail ?? 'usuario'}',
        'Connected as ${googleAuth.currentEmail ?? 'user'}',
      ),
      signedOutLabel: labelBuilder(
        'Não conectado ao Google',
        'Not connected to Google',
      ),
      disconnectLabel: labelBuilder('Desconectar', 'Disconnect'),
      connectLabel: labelBuilder('Conectar ao Google', 'Connect to Google'),
      connectingLabel: labelBuilder('Conectando...', 'Connecting...'),
      errorMessage: googleAuth.error,
      onDisconnect: googleAuth.signOut,
      onConnect: (!oauthOk || isLoading) ? null : onConnect,
    );
  }
}

/// **Molecule** — prompt to configure Google OAuth client credentials.
class GoogleDriveOAuthConfigSection extends StatelessWidget {
  const GoogleDriveOAuthConfigSection({
    required this.labelBuilder,
    required this.onPressed,
    super.key,
  });

  final DestinationDialogLabelBuilder labelBuilder;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OAuthCredentialsSectionCard(
      title: labelBuilder('Configuracao OAuth', 'OAuth configuration'),
      description: labelBuilder(
        'Para usar o Google Drive, configure as credenciais OAuth do Google Cloud Console.',
        'To use Google Drive, configure OAuth credentials in Google Cloud Console.',
      ),
      actionLabel: labelBuilder(
        'Configurar credenciais',
        'Configure credentials',
      ),
      onPressed: onPressed,
    );
  }
}
