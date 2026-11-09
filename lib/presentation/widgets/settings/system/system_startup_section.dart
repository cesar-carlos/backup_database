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
          if (systemSettings.hasStartupRecoveryError) ...[
            InfoBar(
              severity: InfoBarSeverity.error,
              title: Text(
                appLocaleString(
                  context,
                  'Não foi possível restaurar o início automático.',
                  'Could not restore automatic startup.',
                ),
              ),
              content: Text(
                appLocaleString(
                  context,
                  'A configuração do Windows pode diferir da preferência salva. Tente restaurar antes de alterar novamente.',
                  'Windows may differ from the saved preference. Retry restoration before making another change.',
                ),
              ),
              action: Button(
                onPressed: systemSettings.retryStartupRecovery,
                child: Text(
                  appLocaleString(
                    context,
                    'Tentar restaurar',
                    'Retry restoration',
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
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
              'Inicia minimizado na abertura automática com o Windows.',
              'Starts minimized when opening automatically with Windows.',
            ),
            value: systemSettings.startMinimized,
            onChanged: systemSettings.setStartMinimized,
          ),
        ],
      ),
    );
  }
}
