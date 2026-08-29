import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:backup_database/presentation/widgets/molecules/cancel_button.dart';
import 'package:backup_database/presentation/widgets/molecules/schedule_dependency_list.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _dialogContentWidth = 680;

enum DestinationDependencyDialogAction { close, goToSchedules }

/// **Organism** — blocking dialog when a destination has schedule dependencies.
class DestinationDependencyDialog extends StatelessWidget {
  const DestinationDependencyDialog({
    required this.destinationName,
    required this.schedules,
    super.key,
  });

  final String destinationName;
  final List<Schedule> schedules;

  static Future<DestinationDependencyDialogAction?> show(
    BuildContext context, {
    required String destinationName,
    required List<Schedule> schedules,
  }) {
    return showDialog<DestinationDependencyDialogAction>(
      context: context,
      builder: (context) => DestinationDependencyDialog(
        destinationName: destinationName,
        schedules: schedules,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final colors = context.colors;

    return ContentDialog(
      title: Row(
        children: [
          Icon(FluentIcons.warning, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(texts.deletionBlockedByDependencies)),
        ],
      ),
      content: SizedBox(
        width: _dialogContentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'O destino "$destinationName" não pode ser excluído porque '
              'está vinculado a um ou mais agendamentos.',
              style: FluentTheme.of(context).typography.body,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Exclua primeiro os agendamentos abaixo na tela de Agendamentos.',
              style: FluentTheme.of(context).typography.body,
            ),
            const SizedBox(height: AppSpacing.md),
            ScheduleDependencyList(schedules: schedules),
          ],
        ),
      ),
      actions: [
        CancelButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(DestinationDependencyDialogAction.close),
        ),
        AppButton.primary(
          label: texts.goToSchedules,
          onPressed: () => Navigator.of(context).pop(
            DestinationDependencyDialogAction.goToSchedules,
          ),
        ),
      ],
    );
  }
}
