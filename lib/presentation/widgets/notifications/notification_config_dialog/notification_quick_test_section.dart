import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — optional recipient used by the SMTP quick test.
class NotificationQuickTestSection extends StatelessWidget {
  const NotificationQuickTestSection({
    required this.recipientEmailController,
    required this.recipientEmailValidator,
    super.key,
  });

  final TextEditingController recipientEmailController;
  final String? Function(String?) recipientEmailValidator;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: recipientEmailController,
      label: appLocaleString(
        context,
        'E-mail de destino (opcional para teste)',
        'Destination e-mail (optional for test)',
      ),
      keyboardType: TextInputType.emailAddress,
      hint: appLocaleString(
        context,
        'destino@exemplo.com',
        'recipient@example.com',
      ),
      validator: recipientEmailValidator,
    );
  }
}
