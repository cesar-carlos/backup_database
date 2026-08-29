import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — lembrete de fim de avaliação (≤ 30 dias).
class LicenseTrialReminderInfoBar extends StatelessWidget {
  const LicenseTrialReminderInfoBar({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoBar(
      isLong: true,
      title: Text(
        appLocaleString(
          context,
          'Avaliação próxima do fim',
          'Trial ending soon',
        ),
      ),
      content: Text(
        appLocaleString(
          context,
          'O período de avaliação termina em 01/10/2027. '
              'Ative uma licença para manter recursos premium '
              '(nuvem, diferencial, e-mail e outros).',
          'The evaluation period ends on 01 Oct 2027. '
              'Activate a license to keep premium features '
              '(cloud, differential, email and others).',
        ),
      ),
    );
  }
}
