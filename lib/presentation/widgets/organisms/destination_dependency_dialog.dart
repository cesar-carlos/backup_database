import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/organisms/schedule_blocked_deletion_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';

typedef DestinationDependencyDialogAction = DependencyDialogAction;

/// **Organism** — blocking dialog when a destination has schedule
/// dependencies.
class DestinationDependencyDialog {
  DestinationDependencyDialog._();

  static Future<DependencyDialogAction?> show(
    BuildContext context, {
    required String destinationName,
    required List<Schedule> schedules,
  }) {
    return ScheduleBlockedDeletionDialog.show(
      context,
      bodyParagraphs: [
        appLocaleString(
          context,
          'O destino "$destinationName" não pode ser excluído porque '
              'está vinculado a um ou mais agendamentos.',
          'Destination "$destinationName" cannot be deleted because it is '
              'linked to one or more schedules.',
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
