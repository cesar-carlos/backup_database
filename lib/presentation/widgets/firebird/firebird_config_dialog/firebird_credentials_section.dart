import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — username and password for the Firebird login.
class FirebirdCredentialsSection extends StatelessWidget {
  const FirebirdCredentialsSection({
    required this.usernameController,
    required this.passwordController,
    super.key,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: usernameController,
          label: appLocaleString(context, 'Usuário', 'Username'),
          hint: 'SYSDBA',
          validator: (String? value) {
            if (value == null || value.trim().isEmpty) {
              return appLocaleString(
                context,
                'Usuário é obrigatório',
                'Username is required',
              );
            }
            return null;
          },
          prefixIcon: const Icon(FluentIcons.contact),
        ),
        const SizedBox(height: AppSpacing.md),
        PasswordField(
          controller: passwordController,
          hint: appLocaleString(
            context,
            'Senha do usuario',
            'User password',
          ),
        ),
      ],
    );
  }
}
