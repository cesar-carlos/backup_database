import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/atoms/app_icon_button.dart';
import 'package:backup_database/presentation/widgets/atoms/app_status_chip.dart';
import 'package:backup_database/presentation/widgets/atoms/widget_texts.dart';
import 'package:backup_database/presentation/widgets/molecules/config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class ScheduleListItem extends StatelessWidget {
  const ScheduleListItem({
    required this.schedule,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onRunNow,
    this.onToggleEnabled,
    this.onTransferDestinations,
    this.isOperating = false,
  });
  final Schedule schedule;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onRunNow;
  final ValueChanged<bool>? onToggleEnabled;
  final VoidCallback? onTransferDestinations;
  final bool isOperating;

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    final effectivelyDisabled = isOperating || !schedule.enabled;
    final databaseMeta = DatabaseTypeMetadata.of(
      schedule.databaseType,
    );
    final runNowLabel = appLocaleString(
      context,
      'Executar agora',
      'Run now',
    );
    final transferLabel = appLocaleString(
      context,
      'Transferir destinos',
      'Transfer destinations',
    );

    return ConfigListItem(
      name: schedule.name,
      icon: FluentIcons.calendar,
      enabled: schedule.enabled,
      onToggleEnabled: isOperating ? null : onToggleEnabled,
      onEdit: isOperating ? null : onEdit,
      onDuplicate: isOperating ? null : onDuplicate,
      onDelete: isOperating ? null : onDelete,
      trailingAction: isOperating
          ? const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          : onRunNow != null || onTransferDestinations != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onTransferDestinations != null)
                  AppIconButton(
                    label: transferLabel,
                    icon: FluentIcons.fabric_folder,
                    onPressed: onTransferDestinations,
                  ),
                if (onRunNow != null)
                  AppIconButton(
                    label: runNowLabel,
                    icon: FluentIcons.play,
                    onPressed: effectivelyDisabled ? null : onRunNow,
                  ),
              ],
            )
          : null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              AppStatusChip(
                label: texts.scheduleTypeName(
                  scheduleTypeFromString(schedule.scheduleType),
                ),
                color: _scheduleTypeColor(
                  scheduleTypeFromString(schedule.scheduleType),
                ),
              ),
              AppStatusChip(
                label: databaseMeta.chipLabel,
                color: databaseMeta.accentColor,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (schedule.nextRunAt != null)
            Text(
              '${texts.nextRunLabel}: ${DateFormat('dd/MM/yyyy HH:mm').format(schedule.nextRunAt!)}',
              style: FluentTheme.of(context).typography.body,
            ),
          if (schedule.lastRunAt != null)
            Text(
              '${texts.lastRunLabel}: ${DateFormat('dd/MM/yyyy HH:mm').format(schedule.lastRunAt!)}',
              style: FluentTheme.of(context).typography.body?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Color _scheduleTypeColor(ScheduleType type) {
    return switch (type) {
      ScheduleType.daily => AppPalette.scheduleDaily,
      ScheduleType.weekly => AppPalette.scheduleWeekly,
      ScheduleType.monthly => AppPalette.scheduleMonthly,
      ScheduleType.interval => AppPalette.scheduleInterval,
    };
  }
}
