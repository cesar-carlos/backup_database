import 'package:backup_database/application/providers/dropbox_auth_provider.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_dropbox_fields.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_oauth_availability_warning.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_oauth_credentials_card.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_oauth_status_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — Dropbox OAuth status, credentials, folder and warnings.
class DropboxOAuthSlots extends StatelessWidget {
  const DropboxOAuthSlots({
    required this.folderPathController,
    required this.folderNameController,
    required this.labelBuilder,
    required this.onConnect,
    required this.onConfigureCredentials,
    super.key,
  });

  final TextEditingController folderPathController;
  final TextEditingController folderNameController;
  final DestinationDialogLabelBuilder labelBuilder;
  final Future<void> Function(DropboxAuthProvider auth) onConnect;
  final Future<void> Function(DropboxAuthProvider auth) onConfigureCredentials;

  @override
  Widget build(BuildContext context) {
    final dropboxAuth = getIt<DropboxAuthProvider>();

    return ListenableBuilder(
      listenable: dropboxAuth,
      builder: (BuildContext context, _) {
        return DropboxDestinationFields(
          oauthAvailabilityWarning: OAuthAvailabilityWarning.maybeOf(
            context: context,
            labelBuilder: labelBuilder,
          ),
          authStatus: DropboxAuthStatus(
            dropboxAuth: dropboxAuth,
            labelBuilder: labelBuilder,
            onConnect: () => onConnect(dropboxAuth),
          ),
          oauthConfigSection: !dropboxAuth.isSignedIn
              ? DropboxOAuthConfigSection(
                  dropboxAuth: dropboxAuth,
                  labelBuilder: labelBuilder,
                  onPressed: () => onConfigureCredentials(dropboxAuth),
                )
              : null,
          folderFields: DropboxFolderFields(
            folderPathController: folderPathController,
            folderNameController: folderNameController,
            enabled: dropboxAuth.isSignedIn,
            labelBuilder: labelBuilder,
          ),
          notSignedInWarning: !dropboxAuth.isSignedIn
              ? DropboxNotSignedInWarning(labelBuilder: labelBuilder)
              : null,
        );
      },
    );
  }
}

/// **Molecule** — Dropbox folder path and folder name fields.
class DropboxFolderFields extends StatelessWidget {
  const DropboxFolderFields({
    required this.folderPathController,
    required this.folderNameController,
    required this.enabled,
    required this.labelBuilder,
    super.key,
  });

  final TextEditingController folderPathController;
  final TextEditingController folderNameController;
  final bool enabled;
  final DestinationDialogLabelBuilder labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppTextField(
          controller: folderPathController,
          label: labelBuilder(
            'Caminho da pasta (opcional)',
            'Folder path (optional)',
          ),
          hint: labelBuilder(
            '/Backups ou deixe vazio para raiz',
            '/Backups or leave empty for root',
          ),
          prefixIcon: const Icon(FluentIcons.folder),
          enabled: enabled,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: folderNameController,
          label: labelBuilder(
            'Nome da pasta no Dropbox',
            'Dropbox folder name',
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
        ),
      ],
    );
  }
}

/// **Atom** — prompt to sign in before configuring Dropbox.
class DropboxNotSignedInWarning extends StatelessWidget {
  const DropboxNotSignedInWarning({
    required this.labelBuilder,
    super.key,
  });

  final DestinationDialogLabelBuilder labelBuilder;

  @override
  Widget build(BuildContext context) {
    return AppCallout(
      tone: AppCalloutTone.danger,
      message: labelBuilder(
        'Conecte-se ao Dropbox para configurar o destino.',
        'Sign in to Dropbox to configure this destination.',
      ),
    );
  }
}

/// **Molecule** — Dropbox OAuth signed-in/out status card.
class DropboxAuthStatus extends StatelessWidget {
  const DropboxAuthStatus({
    required this.dropboxAuth,
    required this.labelBuilder,
    required this.onConnect,
    super.key,
  });

  final DropboxAuthProvider dropboxAuth;
  final DestinationDialogLabelBuilder labelBuilder;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
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
      signedInLabel: labelBuilder(
        'Conectado como ${dropboxAuth.currentEmail ?? 'usuario'}',
        'Connected as ${dropboxAuth.currentEmail ?? 'user'}',
      ),
      signedOutLabel: labelBuilder(
        'Não conectado ao Dropbox',
        'Not connected to Dropbox',
      ),
      disconnectLabel: labelBuilder('Desconectar', 'Disconnect'),
      connectLabel: labelBuilder(
        'Conectar ao Dropbox',
        'Connect to Dropbox',
      ),
      connectingLabel: labelBuilder('Conectando...', 'Connecting...'),
      errorMessage: dropboxAuth.error,
      onDisconnect: dropboxAuth.signOut,
      onConnect: (!oauthOk || isLoading) ? null : onConnect,
    );
  }
}

/// **Molecule** — prompt to configure Dropbox OAuth client credentials.
class DropboxOAuthConfigSection extends StatelessWidget {
  const DropboxOAuthConfigSection({
    required this.dropboxAuth,
    required this.labelBuilder,
    required this.onPressed,
    super.key,
  });

  final DropboxAuthProvider dropboxAuth;
  final DestinationDialogLabelBuilder labelBuilder;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isConfigured = dropboxAuth.isConfigured;
    final hasClientId = dropboxAuth.oauthConfig?.clientId.isNotEmpty ?? false;

    return OAuthCredentialsSectionCard(
      title: labelBuilder('Configuracao OAuth', 'OAuth configuration'),
      description: isConfigured && hasClientId
          ? labelBuilder(
              'Credenciais OAuth configuradas. Clique em "Alterar credenciais" para modificar.',
              'OAuth credentials configured. Click "Change credentials" to modify.',
            )
          : labelBuilder(
              'Para usar o Dropbox, configure as credenciais OAuth do Dropbox App Console.',
              'To use Dropbox, configure OAuth credentials in Dropbox App Console.',
            ),
      actionLabel: isConfigured && hasClientId
          ? labelBuilder('Alterar credenciais', 'Change credentials')
          : labelBuilder('Configurar credenciais', 'Configure credentials'),
      onPressed: onPressed,
    );
  }
}
