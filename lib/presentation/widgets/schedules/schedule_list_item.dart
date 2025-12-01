import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/schedule.dart';

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
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: schedule.enabled
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.schedule_outlined,
            color: schedule.enabled
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          schedule.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getScheduleTypeColor(schedule.scheduleType).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getScheduleTypeName(schedule.scheduleType),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _getScheduleTypeColor(schedule.scheduleType),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getDatabaseTypeColor(schedule.databaseType).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getDatabaseTypeName(schedule.databaseType),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (schedule.lastRunAt != null)
              Text(
                'Última execução: ${DateFormat('dd/MM/yyyy HH:mm').format(schedule.lastRunAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow_outlined),
              tooltip: 'Executar agora',
              onPressed: schedule.enabled ? onRunNow : null,
            ),
            Switch(
              value: schedule.enabled,
              onChanged: onToggleEnabled,
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit?.call();
                    break;
                  case 'delete':
                    onDelete?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Editar'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Excluir', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
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
        return Colors.blue;
      case ScheduleType.weekly:
        return Colors.green;
      case ScheduleType.monthly:
        return Colors.purple;
      case ScheduleType.interval:
        return Colors.orange;
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
        return Colors.indigo;
      case DatabaseType.sybase:
        return Colors.teal;
    }
  }
}

