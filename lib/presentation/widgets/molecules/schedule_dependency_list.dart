import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/atoms/app_card.dart';
import 'package:backup_database/presentation/widgets/atoms/app_status_chip.dart';
import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _listMaxHeight = 280;
const double _scheduleIconSize = 18;

/// **Molecule** — scrollable list of schedules that block a deletion.
class ScheduleDependencyList extends StatelessWidget {
  const ScheduleDependencyList({required this.schedules, super.key});

  final List<Schedule> schedules;

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _listMaxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: schedules.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final schedule = schedules[index];
          final isEnabled = schedule.enabled;

          return AppCard(
            padding: AppSpacing.paddingMd,
            child: Row(
              children: [
                const Icon(FluentIcons.calendar, size: _scheduleIconSize),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.name,
                        style: FluentTheme.of(context).typography.subtitle
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          AppStatusChip(
                            label: texts.scheduleTypeName(
                              scheduleTypeFromString(schedule.scheduleType),
                            ),
                            color: AppPalette.scheduleDaily,
                          ),
                          AppStatusChip(
                            label: isEnabled ? texts.active : texts.inactive,
                            tone: isEnabled
                                ? AppStatusChipTone.success
                                : AppStatusChipTone.neutral,
                            color: isEnabled ? null : AppPalette.grey600,
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
    );
  }
}
