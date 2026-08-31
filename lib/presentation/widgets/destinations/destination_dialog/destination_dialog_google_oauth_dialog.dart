import 'dart:async';

import 'package:backup_database/application/providers/google_auth_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — Google OAuth client ID / secret configuration dialog.
class OAuthConfigDialog extends StatefulWidget {
  const OAuthConfigDialog({
    required this.googleAuth,
    required this.initialClientId,
    required this.initialClientSecret,
    super.key,
  });

  final GoogleAuthProvider googleAuth;
  final String initialClientId;
  final String initialClientSecret;

  @override
  State<OAuthConfigDialog> createState() => _OAuthConfigDialogState();
}

class _OAuthConfigDialogState extends State<OAuthConfigDialog> {
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
    return AppDialogShell(
      constraints: AppDialogConstraints.of(
        context,
        preferredWidth: 800,
      ),
      title: Row(
        children: [
          const Icon(FluentIcons.cloud),
          const SizedBox(width: AppSpacing.sm),
          Text(
            appLocaleString(
              context,
              'Configurar Google OAuth',
              'Configure Google OAuth',
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
              'Obtenha as credenciais no Google Cloud Console:',
              'Get credentials from Google Cloud Console:',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _GoogleOAuthInstructions(),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _clientIdController,
            label: 'Client ID',
            hint: 'xxx.apps.googleusercontent.com',
            prefixIcon: const Icon(FluentIcons.lock),
            enabled: !_isLoading,
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return appLocaleString(
                  context,
                  'Client ID é obrigatório',
                  'Client ID is required',
                );
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          PasswordField(
            controller: _clientSecretController,
            label: 'Client Secret',
            hint: 'GOCSPX-xxx',
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

class _GoogleOAuthInstructions extends StatelessWidget {
  const _GoogleOAuthInstructions();

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
              '1. Acesse console.cloud.google.com',
              '1. Go to console.cloud.google.com',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            appLocaleString(
              context,
              '2. Crie um projeto ou selecione existente',
              '2. Create a project or select an existing one',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            appLocaleString(
              context,
              '3. Ative a Google Drive API',
              '3. Enable Google Drive API',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          Text(
            appLocaleString(
              context,
              '4. Crie credenciais OAuth (Desktop)',
              '4. Create OAuth credentials (Desktop)',
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            appLocaleString(
              context,
              '5. Na credencial criada, adicione em "URIs de redirecionamento autorizados":',
              '5. In the created credential, add this under "Authorized redirect URIs":',
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
