import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({
    required this.schedules,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onRunNow,
    required this.onToggleEnabled,
    this.scheduleActionsEnabled = true,
    super.key,
  });

  final List<Schedule> schedules;
  final ValueChanged<Schedule> onEdit;
  final ValueChanged<Schedule> onDuplicate;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onRunNow;
  final void Function(Schedule schedule, bool enabled) onToggleEnabled;
  final bool scheduleActionsEnabled;

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    return AppCard(
      child: AppDataGrid<Schedule>(
        minWidth: 900,
        columns: [
          AppDataGridColumn<Schedule>(
            label: texts.scheduleLabel,
            width: const FlexColumnWidth(1.8),
            cellBuilder: (context, row) => Text(
              row.name,
              overflow: TextOverflow.ellipsis,
              style: FluentTheme.of(context).typography.bodyStrong,
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: texts.typeLabel,
            width: const FlexColumnWidth(0.95),
            cellBuilder: (context, row) => AppStatusChip(
              label: texts.scheduleTypeName(
                scheduleTypeFromString(row.scheduleType),
              ),
              color: getScheduleTypeColor(
                scheduleTypeFromString(row.scheduleType),
              ),
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: texts.nextRunLabel,
            width: const FlexColumnWidth(0.95),
            cellBuilder: (context, row) => Text(
              row.nextRunAt != null ? _dateFormat.format(row.nextRunAt!) : '-',
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: texts.lastRunLabel,
            width: const FlexColumnWidth(0.95),
            cellBuilder: (context, row) => Text(
              row.lastRunAt != null ? _dateFormat.format(row.lastRunAt!) : '-',
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: texts.statusLabel,
            width: const FlexColumnWidth(1.2),
            cellBuilder: (context, row) => Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToggleSwitch(
                  checked: row.enabled,
                  onChanged: scheduleActionsEnabled
                      ? (enabled) => onToggleEnabled(row, enabled)
                      : null,
                ),
                Text(row.enabled ? texts.active : texts.inactive),
              ],
            ),
          ),
        ],
        actions: [
          AppDataGridAction<Schedule>(
            icon: FluentIcons.play,
            tooltip: 'Executar agora',
            onPressed: (row) => onRunNow(row.id),
            isEnabled: (row) => scheduleActionsEnabled && row.enabled,
          ),
          AppDataGridAction<Schedule>(
            icon: FluentIcons.edit,
            tooltip: 'Editar',
            onPressed: onEdit,
            isEnabled: (_) => scheduleActionsEnabled,
          ),
          AppDataGridAction<Schedule>(
            icon: FluentIcons.copy,
            tooltip: 'Duplicar',
            onPressed: onDuplicate,
            isEnabled: (_) => scheduleActionsEnabled,
          ),
          AppDataGridAction<Schedule>(
            icon: FluentIcons.delete,
            iconColor: context.colors.danger,
            tooltip: 'Excluir',
            onPressed: (row) => onDelete(row.id),
            isEnabled: (_) => scheduleActionsEnabled,
          ),
        ],
        rows: schedules,
      ),
    );
  }

  Color getScheduleTypeColor(ScheduleType type) {
    switch (type) {
      case ScheduleType.daily:
        return AppPalette.scheduleDaily;
      case ScheduleType.weekly:
        return AppPalette.scheduleWeekly;
      case ScheduleType.monthly:
        return AppPalette.scheduleMonthly;
      case ScheduleType.interval:
        return AppPalette.scheduleInterval;
    }
  }
}
