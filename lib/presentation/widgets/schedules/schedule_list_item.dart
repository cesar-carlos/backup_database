import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/schedule.dart';
import '../common/config_list_item.dart';

class ScheduleListItem extends StatelessWidget {
  final Schedule schedule;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRunNow;
  final ValueChanged<bool>? onToggleEnabled;

  const ScheduleListItem({
    super.key,
    required this.schedule,
    this.onEdit,
    this.onDelete,
    this.onRunNow,
    this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return ConfigListItem(
      name: schedule.name,
      icon: FluentIcons.calendar,
      enabled: schedule.enabled,
      onToggleEnabled: onToggleEnabled,
      onEdit: onEdit,
      onDelete: onDelete,
      trailingAction: onRunNow != null
          ? IconButton(
              icon: const Icon(FluentIcons.play),
              onPressed: schedule.enabled ? onRunNow : null,
            )
          : null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _getScheduleTypeColor(
                    schedule.scheduleType,
                  ).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getScheduleTypeName(schedule.scheduleType),
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: _getScheduleTypeColor(schedule.scheduleType),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _getDatabaseTypeColor(
                    schedule.databaseType,
                  ).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getDatabaseTypeName(schedule.databaseType),
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: _getDatabaseTypeColor(schedule.databaseType),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (schedule.nextRunAt != null)
            Text(
              'Próxima execução: ${DateFormat('dd/MM/yyyy HH:mm').format(schedule.nextRunAt!)}',
              style: FluentTheme.of(context).typography.body,
            ),
          if (schedule.lastRunAt != null)
            Text(
              'Última execução: ${DateFormat('dd/MM/yyyy HH:mm').format(schedule.lastRunAt!)}',
              style: FluentTheme.of(context).typography.body?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorSecondary,
              ),
            ),
        ],
      ),
    );
  }

  String _getScheduleTypeName(ScheduleType type) {
    switch (type) {
      case ScheduleType.daily:
        return 'Diário';
      case ScheduleType.weekly:
        return 'Semanal';
      case ScheduleType.monthly:
        return 'Mensal';
      case ScheduleType.interval:
        return 'Intervalo';
    }
  }

  Color _getScheduleTypeColor(ScheduleType type) {
    switch (type) {
      case ScheduleType.daily:
        return AppColors.scheduleDaily;
      case ScheduleType.weekly:
        return AppColors.scheduleWeekly;
      case ScheduleType.monthly:
        return AppColors.scheduleMonthly;
      case ScheduleType.interval:
        return AppColors.scheduleInterval;
    }
  }

  String _getDatabaseTypeName(DatabaseType type) {
    switch (type) {
      case DatabaseType.sqlServer:
        return 'SQL Server';
      case DatabaseType.sybase:
        return 'Sybase';
    }
  }

  Color _getDatabaseTypeColor(DatabaseType type) {
    switch (type) {
      case DatabaseType.sqlServer:
        return AppColors.databaseSqlServer;
      case DatabaseType.sybase:
        return AppColors.databaseSybase;
    }
  }
}
