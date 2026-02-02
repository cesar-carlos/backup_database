import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/common/config_list_item.dart';
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
    final effectivelyDisabled = isOperating || !schedule.enabled;

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
                      IconButton(
                        icon: const Icon(FluentIcons.fabric_folder),
                        onPressed: onTransferDestinations,
                      ),
                    if (onRunNow != null)
                      IconButton(
                        icon: const Icon(FluentIcons.play),
                        onPressed: effectivelyDisabled ? null : onRunNow,
                      ),
                  ],
                )
              : null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getScheduleTypeColor(
                    schedule.scheduleType,
                  ).withValues(alpha: 0.1),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getDatabaseTypeColor(
                    schedule.databaseType,
                  ).withValues(alpha: 0.1),
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
      case DatabaseType.postgresql:
        return 'PostgreSQL';
    }
  }

  Color _getDatabaseTypeColor(DatabaseType type) {
    switch (type) {
      case DatabaseType.sqlServer:
        return AppColors.databaseSqlServer;
      case DatabaseType.sybase:
        return AppColors.databaseSybase;
      case DatabaseType.postgresql:
        return AppColors.databasePostgresql;
    }
  }
}
