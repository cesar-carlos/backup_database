import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

/// **Molecule** — warning when a pasted key is expired but trial still
/// covers the device.
class LicenseStatusBanner extends StatelessWidget {
  const LicenseStatusBanner({required this.stored, super.key});

  final License stored;

  static bool shouldShow(LicenseProvider provider) {
    final stored = provider.storedLicense;
    return provider.isTrialActive && stored != null && stored.isExpired;
  }

  @override
  Widget build(BuildContext context) {
    return InfoBar(
      severity: InfoBarSeverity.warning,
      isLong: true,
      title: Text(
        appLocaleString(
          context,
          'Licença expirada — avaliação ainda cobre',
          'Expired license — evaluation still covers you',
        ),
      ),
      content: Text(
        stored.expiresAt != null
            ? appLocaleString(
                context,
                'A chave colada expirou em ${DateFormat('dd/MM/yyyy HH:mm').format(stored.expiresAt!)}. '
                    'Renove para continuar com premium após o trial.',
                'The pasted key expired on ${DateFormat('dd/MM/yyyy HH:mm').format(stored.expiresAt!)}. '
                    'Renew to keep premium after the trial.',
              )
            : appLocaleString(
                context,
                'A chave colada está expirada. Renove para continuar '
                    'com premium após o trial.',
                'The pasted key is expired. Renew to keep premium '
                    'after the trial.',
              ),
      ),
    );
  }
}
