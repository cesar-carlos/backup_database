import 'package:backup_database/application/services/admin_password_verifier.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// **Organism** — admin password gate for the debug license generator.
class LicenseAuthDialog extends StatefulWidget {
  const LicenseAuthDialog({
    required this.adminVerifier,
    required this.onAuthenticated,
    super.key,
  });

  final AdminPasswordVerifier adminVerifier;
  final VoidCallback onAuthenticated;

  @override
  State<LicenseAuthDialog> createState() => _LicenseAuthDialogState();
}

class _LicenseAuthDialogState extends State<LicenseAuthDialog> {
  final TextEditingController _passwordController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  String? _localizeAdminVerification(VerificationResult result) {
    if (result.isSuccess) return null;
    if (result.isNotConfigured) {
      return appLocaleString(
        context,
        'Gerador desabilitado: LICENSE_ADMIN_PASSWORD_HASH não configurada '
            'no .env externo.',
        'Generator disabled: LICENSE_ADMIN_PASSWORD_HASH not configured '
            'in external .env.',
      );
    }
    if (result.isLockedOut) {
      return appLocaleString(
        context,
        'Bloqueado por excesso de tentativas. Aguarde alguns segundos.',
        'Locked out due to repeated failures. Wait a few seconds.',
      );
    }
    return appLocaleString(context, 'Senha incorreta', 'Incorrect password');
  }

  void _submit() {
    final enteredPassword = _passwordController.text.trim();
    if (enteredPassword.isEmpty) {
      setState(() {
        _errorMessage = appLocaleString(
          context,
          'Senha não pode estar vazia',
          'Password cannot be empty',
        );
      });
      return;
    }

    final storedHash = dotenv.env['LICENSE_ADMIN_PASSWORD_HASH'] ?? '';
    final result = widget.adminVerifier.verify(
      enteredPassword: enteredPassword,
      storedHash: storedHash,
    );
    final localizedError = _localizeAdminVerification(result);
    if (localizedError == null) {
      Navigator.pop(context);
      widget.onAuthenticated();
      return;
    }
    setState(() => _errorMessage = localizedError);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Row(
        children: [
          const Icon(FluentIcons.lock),
          const SizedBox(width: AppSpacing.sm),
          Text(appLocaleString(context, 'Autenticação', 'Authentication')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocaleString(
              context,
              'Digite a senha de administrador para acessar o gerador de licenças:',
              'Enter admin password to access license generator:',
            ),
          ),
          AppSpacing.gapMd,
          PasswordField(
            controller: _passwordController,
            hint: appLocaleString(
              context,
              'Digite a senha',
              'Enter password',
            ),
          ),
          if (_errorMessage != null) ...[
            AppSpacing.gapMd,
            InfoBar(
              severity: InfoBarSeverity.error,
              title: Text(appLocaleString(context, 'Erro', 'Error')),
              content: Text(_errorMessage!),
            ),
          ],
        ],
      ),
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context)),
        AppButton.primary(
          label: appLocaleString(context, 'Entrar', 'Sign in'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
