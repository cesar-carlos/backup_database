import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — configuration name and SMTP account e-mail.
class NotificationIdentificationSection extends StatelessWidget {
  const NotificationIdentificationSection({
    required this.configNameController,
    required this.emailController,
    required this.configNameValidator,
    required this.emailValidator,
    super.key,
  });

  final TextEditingController configNameController;
  final TextEditingController emailController;
  final String? Function(String?) configNameValidator;
  final String? Function(String?) emailValidator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: configNameController,
          label: appLocaleString(
            context,
            'Nome da configuração',
            'Configuration name',
          ),
          hint: appLocaleString(context, 'SMTP principal', 'Primary SMTP'),
          validator: configNameValidator,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: emailController,
          label: appLocaleString(
            context,
            'E-mail da conta SMTP',
            'SMTP account e-mail',
          ),
          keyboardType: TextInputType.emailAddress,
          hint: appLocaleString(
            context,
            'seu-email@exemplo.com',
            'your-email@example.com',
          ),
          validator: emailValidator,
        ),
      ],
    );
  }
}
