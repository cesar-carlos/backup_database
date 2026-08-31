import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ServiceLocalScheduleTimerSection extends StatelessWidget {
  const ServiceLocalScheduleTimerSection({
    required this.isLoading,
    required this.enabled,
    required this.onChanged,
    this.serviceOwnsScheduler = false,
    super.key,
  });

  final bool isLoading;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool serviceOwnsScheduler;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Agendamento automático local',
        'Local automatic scheduling',
      ),
      description: appLocaleString(
        context,
        'Controla o timer local que verifica agendamentos vencidos.',
        'Controls the local timer that checks for due schedules.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoading)
            const ProgressRing()
          else
            SettingsToggleRow(
              title: appLocaleString(
                context,
                'Timer de verificação de agendamentos',
                'Schedule check timer',
              ),
              description: appLocaleString(
                context,
                'Quando desativado, apenas execuções manuais e comandos remotos continuam ativos.',
                'When off, only manual runs and remote commands continue to work.',
              ),
              value: enabled,
              onChanged: onChanged,
            ),
          if (!isLoading && serviceOwnsScheduler) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Serviço em execução',
                  'Service is running',
                ),
              ),
              content: Text(
                appLocaleString(
                  context,
                  'O timer de agendamento é do serviço do Windows neste computador. A preferência foi salva; reinicie o serviço para aplicar. Este aplicativo não inicia o agendador local enquanto o serviço estiver RUNNING.',
                  'The schedule timer belongs to the Windows service on this computer. The preference was saved; restart the service to apply it. This app does not start the local scheduler while the service is RUNNING.',
                ),
              ),
              isLong: true,
            ),
          ] else if (!isLoading && !enabled) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Reinício recomendado',
                  'Restart recommended',
                ),
              ),
              content: Text(
                appLocaleString(
                  context,
                  'Reinicie o serviço do Windows ou o app em modo servidor para aplicar a preferência ao processo em background.',
                  'Restart the Windows service or the app in server mode so the background process applies this preference.',
                ),
              ),
              isLong: true,
            ),
          ],
        ],
      ),
    );
  }
}
