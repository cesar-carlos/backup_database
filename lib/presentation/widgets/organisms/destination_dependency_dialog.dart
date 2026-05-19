import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/core/theme/tokens/app_radius.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/atoms/app_card.dart';
import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:backup_database/presentation/widgets/molecules/cancel_button.dart';
import 'package:fluent_ui/fluent_ui.dart';

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
        width: 680,
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: schedules.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final schedule = schedules[index];
                  final isEnabled = schedule.enabled;

                  return AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(FluentIcons.calendar, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                schedule.name,
                                style: FluentTheme.of(context)
                                    .typography
                                    .subtitle
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  _Tag(
                                    label: _getScheduleTypeLabel(
                                      scheduleTypeFromString(
                                        schedule.scheduleType,
                                      ),
                                      texts,
                                    ),
                                    color: AppPalette.scheduleDaily,
                                  ),
                                  _Tag(
                                    label: isEnabled
                                        ? texts.active
                                        : texts.inactive,
                                    color: isEnabled
                                        ? AppPalette.success
                                        : AppPalette.grey600,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        CancelButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(DestinationDependencyDialogAction.close),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            DestinationDependencyDialogAction.goToSchedules,
          ),
          child: Text(texts.goToSchedules),
        ),
      ],
    );
  }

  String _getScheduleTypeLabel(ScheduleType type, WidgetTexts texts) {
    return texts.scheduleTypeName(type);
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.circularSm,
      ),
      child: Text(
        label,
        style: FluentTheme.of(
          context,
        ).typography.caption?.copyWith(color: color),
      ),
    );
  }
}
