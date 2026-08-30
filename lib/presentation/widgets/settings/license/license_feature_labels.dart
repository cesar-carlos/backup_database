import 'package:backup_database/core/constants/license_features.dart';
import 'package:fluent_ui/fluent_ui.dart';

String licenseFeatureLabel(BuildContext context, String feature) {
  final isPt =
      Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
  if (!isPt) return feature;

  const labels = {
    LicenseFeatures.differentialBackup: 'Backup diferencial',
    LicenseFeatures.logBackup: 'Backup de logs',
    LicenseFeatures.intervalSchedule: 'Agendamento por interval',
    LicenseFeatures.serverConnection: 'Conexão ao servidor',
    LicenseFeatures.googleDrive: 'Google Drive',
    LicenseFeatures.dropbox: 'Dropbox',
    LicenseFeatures.nextcloud: 'Nextcloud',
    LicenseFeatures.verifyIntegrity: 'Verificação de integridade',
    LicenseFeatures.checksum: 'Verificação de checksum',
    LicenseFeatures.postBackupScript: 'Script pós-backup',
    LicenseFeatures.emailNotification: 'Notificação por e-mail',
  };
  return labels[feature] ?? feature;
}
