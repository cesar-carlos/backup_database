import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — Nextcloud URL, credentials, path and connection test.
class NextcloudDestinationFields extends StatelessWidget {
  const NextcloudDestinationFields({
    required this.serverUrlController,
    required this.usernameController,
    required this.appPasswordController,
    required this.remotePathController,
    required this.folderNameController,
    required this.authMode,
    required this.allowInvalidCertificates,
    required this.isTestingConnection,
    required this.labelBuilder,
    required this.onAuthModeChanged,
    required this.onAllowInvalidCertificatesChanged,
    required this.onTestConnection,
    super.key,
  });

  final TextEditingController serverUrlController;
  final TextEditingController usernameController;
  final TextEditingController appPasswordController;
  final TextEditingController remotePathController;
  final TextEditingController folderNameController;
  final NextcloudAuthMode authMode;
  final bool allowInvalidCertificates;
  final bool isTestingConnection;
  final DestinationDialogLabelBuilder labelBuilder;
  final ValueChanged<NextcloudAuthMode> onAuthModeChanged;
  final ValueChanged<bool> onAllowInvalidCertificatesChanged;
  final VoidCallback onTestConnection;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppTextField(
          controller: serverUrlController,
          label: labelBuilder('URL do Nextcloud', 'Nextcloud URL'),
          hint: 'https://cloud.exemplo.com',
          prefixIcon: const Icon(FluentIcons.globe),
          validator: _validateServerUrl,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: usernameController,
          label: labelBuilder('Usuário', 'Username'),
          hint: 'usuario',
          prefixIcon: const Icon(FluentIcons.contact),
          validator: _validateUsername,
        ),
        const SizedBox(height: AppSpacing.md),
        AppDropdown<NextcloudAuthMode>(
          label: labelBuilder('Tipo de credencial', 'Credential type'),
          value: authMode,
          placeholder: Text(
            labelBuilder('Tipo de credencial', 'Credential type'),
          ),
          items: NextcloudAuthMode.values.map((NextcloudAuthMode mode) {
            final label = mode == NextcloudAuthMode.appPassword
                ? labelBuilder(
                    'App Password (recomendado)',
                    'App Password (recommended)',
                  )
                : labelBuilder('Senha do usuario', 'User password');
            return ComboBoxItem<NextcloudAuthMode>(
              value: mode,
              child: Text(label),
            );
          }).toList(),
          onChanged: (NextcloudAuthMode? value) {
            if (value != null) {
              onAuthModeChanged(value);
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: appPasswordController,
          label: authMode == NextcloudAuthMode.appPassword
              ? labelBuilder('App Password', 'App Password')
              : labelBuilder('Senha do usuario', 'User password'),
          hint: authMode == NextcloudAuthMode.appPassword
              ? labelBuilder(
                  'Senha de aplicativo do Nextcloud',
                  'Nextcloud app password',
                )
              : labelBuilder(
                  'Senha do usuario do Nextcloud',
                  'Nextcloud user password',
                ),
          prefixIcon: const Icon(FluentIcons.lock),
          obscureText: true,
          validator: _validatePassword,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: remotePathController,
          label: labelBuilder(
            'Caminho remoto (opcional)',
            'Remote path (optional)',
          ),
          hint: '/ ou /Backups',
          prefixIcon: const Icon(FluentIcons.folder),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: folderNameController,
          label: labelBuilder('Nome da pasta', 'Folder name'),
          hint: 'Backups',
          prefixIcon: const Icon(FluentIcons.cloud),
          validator: _validateFolderName,
        ),
        const SizedBox(height: AppSpacing.md),
        LabeledToggle(
          title: labelBuilder(
            'Permitir certificado invalido (self-signed)',
            'Allow invalid certificate (self-signed)',
          ),
          description: labelBuilder(
            'Use apenas se seu Nextcloud usa certificado self-signed ou CA interna.',
            'Use only if your Nextcloud uses self-signed cert or internal CA.',
          ),
          value: allowInvalidCertificates,
          onChanged: onAllowInvalidCertificatesChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: labelBuilder(
            'Testar conexao Nextcloud',
            'Test Nextcloud connection',
          ),
          icon: FluentIcons.network_tower,
          onPressed: onTestConnection,
          isLoading: isTestingConnection,
        ),
      ],
    );
  }

  String? _validateServerUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return labelBuilder('URL e obrigatoria', 'URL is required');
    }

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return labelBuilder('URL invalida', 'Invalid URL');
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return labelBuilder('Use http ou https', 'Use http or https');
    }
    return null;
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return labelBuilder('Usuário é obrigatório', 'Username is required');
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return authMode == NextcloudAuthMode.appPassword
          ? labelBuilder(
              'App Password é obrigatório',
              'App Password is required',
            )
          : labelBuilder(
              'Senha do usuario e obrigatoria',
              'User password is required',
            );
    }
    return null;
  }

  String? _validateFolderName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return labelBuilder(
        'Nome da pasta é obrigatório',
        'Folder name is required',
      );
    }
    return null;
  }
}
