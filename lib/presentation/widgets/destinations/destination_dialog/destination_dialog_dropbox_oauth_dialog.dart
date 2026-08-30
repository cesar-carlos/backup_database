import 'dart:async';

import 'package:backup_database/application/providers/dropbox_auth_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — Dropbox OAuth app key / secret configuration dialog.
class DropboxOAuthConfigDialog extends StatefulWidget {
  const DropboxOAuthConfigDialog({
    required this.dropboxAuth,
    required this.initialClientId,
    required this.initialClientSecret,
    super.key,
  });

  final DropboxAuthProvider dropboxAuth;
  final String initialClientId;
  final String initialClientSecret;

  @override
  State<DropboxOAuthConfigDialog> createState() =>
      _DropboxOAuthConfigDialogState();
}

class _DropboxOAuthConfigDialogState extends State<DropboxOAuthConfigDialog> {
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
      unawaited(
        MessageModal.showError(
          context,
          message: appLocaleString(
            context,
            'Client ID é obrigatório',
            'Client ID is required',
          ),
        ),
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
    return AppDialogShell(
      constraints: const BoxConstraints(maxWidth: 800, maxHeight: 760),
      title: Row(
        children: [
          const Icon(FluentIcons.cloud),
          const SizedBox(width: AppSpacing.sm),
          Text(
            appLocaleString(
              context,
              'Configurar Dropbox OAuth',
              'Configure Dropbox OAuth',
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocaleString(
              context,
              'Obtenha as credenciais no Dropbox App Console:',
              'Get credentials from Dropbox App Console:',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _DropboxOAuthInstructions(),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _clientIdController,
            label: 'App Key',
            hint: 'xxxxx',
            prefixIcon: const Icon(FluentIcons.lock),
            enabled: !_isLoading,
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return appLocaleString(
                  context,
                  'App Key é obrigatório',
                  'App Key is required',
                );
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          PasswordField(
            controller: _clientSecretController,
            label: 'App Secret',
            hint: 'xxxxx',
            enabled: !_isLoading,
          ),
        ],
      ),
      actions: [
        CancelButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
        ),
        SaveButton(onPressed: _save, isLoading: _isLoading),
      ],
    );
  }
}

class _DropboxOAuthInstructions extends StatelessWidget {
  const _DropboxOAuthInstructions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: AppRadius.circularMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocaleString(
              context,
              '1. Acesse dropbox.com/developers/apps',
              '1. Go to dropbox.com/developers/apps',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            appLocaleString(
              context,
              '2. Clique em "Create app"',
              '2. Click "Create app"',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            appLocaleString(
              context,
              '3. Escolha "Scoped access" e "Full Dropbox"',
              '3. Choose "Scoped access" and "Full Dropbox"',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            appLocaleString(
              context,
              '4. Configure os scopes: files.content.write, files.content.read, account_info.read',
              '4. Configure scopes: files.content.write, files.content.read, account_info.read',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            appLocaleString(
              context,
              '5. Na seção "OAuth 2", adicione em "Redirect URIs":',
              '5. In section "OAuth 2", add this in "Redirect URIs":',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.colors.info.withValues(alpha: 0.1),
              borderRadius: AppRadius.circularSm,
            ),
            child: SelectableText(
              'http://localhost:8085/oauth2redirect',
              style: FluentTheme.of(context).typography.caption?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            appLocaleString(
              context,
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
