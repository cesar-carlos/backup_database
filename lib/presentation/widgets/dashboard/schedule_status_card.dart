import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ScheduleStatusCard extends StatelessWidget {
  const ScheduleStatusCard({required this.schedule, super.key, this.onExecute});
  final Schedule schedule;
  final VoidCallback? onExecute;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          schedule.enabled ? Icons.schedule : Icons.schedule_outlined,
          color: schedule.enabled ? AppColors.success : AppColors.grey600,
        ),
        title: Text(schedule.name),
        subtitle: Text(
          schedule.nextRunAt != null
              ? 'Próxima execução: ${DateFormat('dd/MM/yyyy HH:mm').format(schedule.nextRunAt!)}'
              : 'Sem próxima execução',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: schedule.enabled ? onExecute : null,
          tooltip: 'Executar agora',
        ),
      ),
    );
  }
}
