import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/common/app_card.dart';
import 'package:backup_database/presentation/widgets/common/cancel_button.dart';
import 'package:backup_database/presentation/widgets/common/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum DependencyDialogAction { close, goToSchedules }

class DatabaseConfigDependencyDialog extends StatelessWidget {
  const DatabaseConfigDependencyDialog({
    required this.databaseLabel,
    required this.configName,
    required this.schedules,
    super.key,
  });

  final String databaseLabel;
  final String configName;
  final List<Schedule> schedules;

  static Future<DependencyDialogAction?> show(
    BuildContext context, {
    required String databaseLabel,
    required String configName,
    required List<Schedule> schedules,
  }) {
    return showDialog<DependencyDialogAction>(
      context: context,
      builder: (context) => DatabaseConfigDependencyDialog(
        databaseLabel: databaseLabel,
        configName: configName,
        schedules: schedules,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);

    return ContentDialog(
      title: Row(
        children: [
          const Icon(FluentIcons.warning, color: AppColors.warning),
          const SizedBox(width: 8),
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
              'A configuração "$configName" ($databaseLabel) não pode ser '
              'excluida porque possui agendamentos vinculados.',
              style: FluentTheme.of(context).typography.body,
            ),
            const SizedBox(height: 8),
            Text(
              'Exclua primeiro os agendamentos abaixo na tela de '
              'Agendamentos.',
              style: FluentTheme.of(context).typography.body,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: schedules.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final schedule = schedules[index];
                  final isEnabled = schedule.enabled;

                  return AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(FluentIcons.calendar, size: 18),
                        const SizedBox(width: 12),
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
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _Tag(
                                    label: _getScheduleTypeLabel(
                                      scheduleTypeFromString(
                                        schedule.scheduleType,
                                      ),
                                      texts,
                                    ),
                                    color: AppColors.scheduleDaily,
                                  ),
                                  _Tag(
                                    label: isEnabled
                                        ? texts.active
                                        : texts.inactive,
                                    color: isEnabled
                                        ? AppColors.success
                                        : AppColors.grey600,
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
          onPressed: () =>
              Navigator.of(context).pop(DependencyDialogAction.close),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(DependencyDialogAction.goToSchedules),
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
        borderRadius: BorderRadius.circular(4),
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
