import 'package:backup_database/core/theme/app_colors.dart';
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
    super.key,
  });

  final List<Schedule> schedules;
  final ValueChanged<Schedule> onEdit;
  final ValueChanged<Schedule> onDuplicate;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onRunNow;
  final void Function(Schedule schedule, bool enabled) onToggleEnabled;

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final texts = WidgetTexts.fromContext(context);
    return AppCard(
      child: AppDataGrid<Schedule>(
        minWidth: 1120,
        columns: [
          AppDataGridColumn<Schedule>(
            label: 'Agendamento',
            width: const FlexColumnWidth(2.2),
            cellBuilder: (context, row) => Text(
              row.name,
              overflow: TextOverflow.ellipsis,
              style: FluentTheme.of(context).typography.bodyStrong,
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: 'Tipo',
            width: const FlexColumnWidth(1.2),
            cellBuilder: (context, row) => _TagChip(
              label: texts.scheduleTypeName(row.scheduleType),
              color: _getScheduleTypeColor(row.scheduleType),
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: 'Banco',
            width: const FlexColumnWidth(1.2),
            cellBuilder: (context, row) => _TagChip(
              label: _getDatabaseTypeName(row.databaseType),
              color: _getDatabaseTypeColor(row.databaseType),
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: texts.nextRunLabel,
            width: const FlexColumnWidth(1.5),
            cellBuilder: (context, row) => Text(
              row.nextRunAt != null ? _dateFormat.format(row.nextRunAt!) : '-',
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: texts.lastRunLabel,
            width: const FlexColumnWidth(1.5),
            cellBuilder: (context, row) => Text(
              row.lastRunAt != null ? _dateFormat.format(row.lastRunAt!) : '-',
            ),
          ),
          AppDataGridColumn<Schedule>(
            label: 'Status',
            width: const FlexColumnWidth(1.3),
            cellBuilder: (context, row) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToggleSwitch(
                  checked: row.enabled,
                  onChanged: (enabled) => onToggleEnabled(row, enabled),
                ),
                const SizedBox(width: 8),
                Text(row.enabled ? 'Ativo' : 'Inativo'),
              ],
            ),
          ),
        ],
        actions: [
          AppDataGridAction<Schedule>(
            icon: FluentIcons.play,
            tooltip: 'Executar agora',
            onPressed: (row) => onRunNow(row.id),
            isEnabled: (row) => row.enabled,
          ),
          AppDataGridAction<Schedule>(
            icon: FluentIcons.edit,
            tooltip: 'Editar',
            onPressed: onEdit,
          ),
          AppDataGridAction<Schedule>(
            icon: FluentIcons.copy,
            tooltip: 'Duplicar',
            onPressed: onDuplicate,
          ),
          AppDataGridAction<Schedule>(
            icon: FluentIcons.delete,
            iconColor: AppColors.error,
            tooltip: 'Excluir',
            onPressed: (row) => onDelete(row.id),
          ),
        ],
        rows: schedules,
      ),
    );
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

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: FluentTheme.of(context).typography.caption?.copyWith(
          color: color,
        ),
      ),
    );
  }
}
