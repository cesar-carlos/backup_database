import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — SMTP host, port and password fields.
class NotificationServerSection extends StatelessWidget {
  const NotificationServerSection({
    required this.smtpServerController,
    required this.smtpPortController,
    required this.passwordController,
    required this.smtpServerValidator,
    required this.passwordValidator,
    required this.authMode,
    super.key,
  });

  final TextEditingController smtpServerController;
  final TextEditingController smtpPortController;
  final TextEditingController passwordController;
  final String? Function(String?) smtpServerValidator;
  final String? Function(String?) passwordValidator;
  final SmtpAuthMode authMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: smtpServerController,
          label: appLocaleString(context, 'Servidor SMTP', 'SMTP server'),
          hint: appLocaleString(
            context,
            'smtp.exemplo.com',
            'smtp.example.com',
          ),
          validator: smtpServerValidator,
        ),
        const SizedBox(height: 16),
        NumericField(
          controller: smtpPortController,
          label: appLocaleString(context, 'Porta', 'Port'),
          hint: '587',
          prefixIcon: FluentIcons.number_field,
          minValue: 1,
          maxValue: 65535,
        ),
        const SizedBox(height: 16),
        PasswordField(
          controller: passwordController,
          label: appLocaleString(context, 'Senha SMTP', 'SMTP password'),
          hint: appLocaleString(
            context,
            'Senha da conta de envio',
            'Password for the sending account',
          ),
          validator: passwordValidator,
          enabled: authMode == SmtpAuthMode.password,
        ),
      ],
    );
  }
}
