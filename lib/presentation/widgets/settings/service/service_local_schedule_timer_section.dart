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
    super.key,
  });

  final bool isLoading;
  final bool enabled;
  final ValueChanged<bool> onChanged;

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
          if (!isLoading && !enabled) ...[
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
