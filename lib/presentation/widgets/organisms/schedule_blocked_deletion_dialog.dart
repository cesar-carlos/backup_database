import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:backup_database/presentation/widgets/molecules/cancel_button.dart';
import 'package:backup_database/presentation/widgets/molecules/schedule_dependency_list.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _dialogContentWidth = 680;

enum DependencyDialogAction { close, goToSchedules }

/// **Organism** — blocking dialog when deletion is prevented by schedules.
class ScheduleBlockedDeletionDialog extends StatelessWidget {
  const ScheduleBlockedDeletionDialog({
    required this.bodyParagraphs,
    required this.schedules,
    super.key,
  });

  final List<String> bodyParagraphs;
  final List<Schedule> schedules;

  static Future<DependencyDialogAction?> show(
    BuildContext context, {
    required List<String> bodyParagraphs,
    required List<Schedule> schedules,
  }) {
    return showDialog<DependencyDialogAction>(
      context: context,
      builder: (context) => ScheduleBlockedDeletionDialog(
        bodyParagraphs: bodyParagraphs,
        schedules: schedules,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final colors = context.colors;
    final bodyStyle = FluentTheme.of(context).typography.body;

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
            for (var i = 0; i < bodyParagraphs.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              Text(bodyParagraphs[i], style: bodyStyle),
            ],
            const SizedBox(height: AppSpacing.md),
            ScheduleDependencyList(schedules: schedules),
          ],
        ),
      ),
      actions: [
        CancelButton(
          onPressed: () =>
              Navigator.of(context).pop(DependencyDialogAction.close),
        ),
        AppButton.primary(
          label: texts.goToSchedules,
          onPressed: () => Navigator.of(
            context,
          ).pop(DependencyDialogAction.goToSchedules),
        ),
      ],
    );
  }
}
