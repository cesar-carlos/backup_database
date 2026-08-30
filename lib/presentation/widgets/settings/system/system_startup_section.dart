import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — start-with-Windows and start-minimized toggles.
class SystemStartupSection extends StatelessWidget {
  const SystemStartupSection({
    required this.systemSettings,
    required this.features,
    super.key,
  });

  final SystemSettingsProvider systemSettings;
  final FeatureAvailabilityService features;

  @override
  Widget build(BuildContext context) {
    final startupDisabledReason = !features.isStartupAtLogonTaskEnabled
        ? localizeCompatibilityReason(
            context,
            reason: features.startupAtLogonTaskDisabledReason,
            fallbackPt: 'A tarefa de inicio no logon nao esta disponivel nesta versao do Windows.',
            fallbackEn:
                'Logon startup task is not available on this Windows version.',
          )
        : null;

    return AppSectionCard(
      title: appLocaleString(context, 'Inicializacao', 'Startup'),
      description: appLocaleString(
        context,
        'Preferencias de arranque da aplicacao na maquina atual.',
        'Startup preferences for the current machine.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Iniciar com o Windows',
              'Start with Windows',
            ),
            description: currentAppMode == AppMode.server
                ? appLocaleString(
                    context,
                    'No modo servidor, o arranque automatico real e controlado pela aba Servico Windows.',
                    'In server mode, real automatic startup is controlled from the Windows Service tab.',
                  )
                : appLocaleString(
                    context,
                    'Cria ou remove a tarefa de arranque para esta instalacao.',
                    'Creates or removes the startup task for this installation.',
                  ),
            value: systemSettings.startWithWindows,
            onChanged: features.isStartupAtLogonTaskEnabled
                ? systemSettings.setStartWithWindows
                : null,
            disabledReason: startupDisabledReason,
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Iniciar minimizado',
              'Start minimized',
            ),
            description: appLocaleString(
              context,
              'Abre a aplicacao ja minimizada na proxima inicializacao.',
              'Opens the application minimized on the next startup.',
            ),
            value: systemSettings.startMinimized,
            onChanged: systemSettings.setStartMinimized,
          ),
        ],
      ),
    );
  }
}
