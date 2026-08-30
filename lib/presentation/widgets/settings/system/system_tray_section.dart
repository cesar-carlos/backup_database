import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — minimize-to-tray and close-to-tray toggles.
class SystemTraySection extends StatelessWidget {
  const SystemTraySection({
    required this.systemSettings,
    required this.features,
    super.key,
  });

  final SystemSettingsProvider systemSettings;
  final FeatureAvailabilityService features;

  @override
  Widget build(BuildContext context) {
    final trayDisabledReason = !features.isTrayEnabled
        ? localizeCompatibilityReason(
            context,
            reason: features.trayDisabledReason,
            fallbackPt: 'A bandeja do sistema nao esta disponivel nesta versao do Windows.',
            fallbackEn: 'System tray is not available on this Windows version.',
          )
        : null;

    return AppSectionCard(
      title: appLocaleString(context, 'Bandeja', 'Tray'),
      description: appLocaleString(
        context,
        'Define como a janela se comporta ao minimizar ou fechar.',
        'Defines how the window behaves when minimizing or closing.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Minimizar para bandeja',
              'Minimize to tray',
            ),
            description: appLocaleString(
              context,
              'Mantem o app em segundo plano ao minimizar a janela.',
              'Keeps the app running in the background when the window is minimized.',
            ),
            value: systemSettings.minimizeToTray,
            onChanged: features.isTrayEnabled
                ? systemSettings.setMinimizeToTray
                : null,
            disabledReason: trayDisabledReason,
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Fechar para bandeja',
              'Close to tray',
            ),
            description: appLocaleString(
              context,
              'Fecha a janela principal, mas mantem o processo na bandeja.',
              'Closes the main window while keeping the process in the system tray.',
            ),
            value: systemSettings.closeToTray,
            onChanged: features.isTrayEnabled
                ? systemSettings.setCloseToTray
                : null,
            disabledReason: trayDisabledReason,
          ),
        ],
      ),
    );
  }
}
