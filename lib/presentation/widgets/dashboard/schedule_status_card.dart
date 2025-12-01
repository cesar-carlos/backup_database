import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/schedule.dart';

class ScheduleStatusCard extends StatelessWidget {
  final Schedule schedule;
  final VoidCallback? onExecute;

  const ScheduleStatusCard({
    super.key,
    required this.schedule,
    this.onExecute,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          schedule.enabled ? Icons.schedule : Icons.schedule_outlined,
          color: schedule.enabled ? Colors.green : Colors.grey,
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

