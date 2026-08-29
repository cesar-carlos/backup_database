import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/organisms/schedule_blocked_deletion_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — blocking dialog when a database config has schedule
/// dependencies.
class DatabaseConfigDependencyDialog {
  DatabaseConfigDependencyDialog._();

  static Future<DependencyDialogAction?> show(
    BuildContext context, {
    required String databaseLabel,
    required String configName,
    required List<Schedule> schedules,
  }) {
    return ScheduleBlockedDeletionDialog.show(
      context,
      bodyParagraphs: [
        appLocaleString(
          context,
          'A configuração "$configName" ($databaseLabel) não pode ser '
              'excluída porque possui agendamentos vinculados.',
          'Configuration "$configName" ($databaseLabel) cannot be deleted '
              'because it has linked schedules.',
        ),
        appLocaleString(
          context,
          'Exclua primeiro os agendamentos abaixo na tela de Agendamentos.',
          'Delete the schedules below on the Schedules screen first.',
        ),
      ],
      schedules: schedules,
    );
  }
}
