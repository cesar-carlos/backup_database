import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Schedule _sampleSchedule({
  required String id,
  required String name,
  required DatabaseType databaseType,
  required String scheduleType,
  bool enabled = true,
}) {
  return Schedule.raw(
    id: id,
    name: name,
    databaseConfigId: 'db-$id',
    databaseType: databaseType,
    scheduleType: scheduleType,
    scheduleConfig: '{}',
    destinationIds: const ['dest-1'],
    backupFolder: 'D:/Backups',
    compressionFormat: CompressionFormat.none,
    enabled: enabled,
    nextRunAt: DateTime(2026, 5, 20, 8),
    lastRunAt: DateTime(2026, 5, 19, 6, 30),
  );
}

@widgetbook.UseCase(name: 'Default', type: ScheduleGrid)
Widget buildScheduleGridUseCase(BuildContext context) {
  return ScheduleGrid(
    schedules: [
      _sampleSchedule(
        id: '1',
        name: 'SQL Daily',
        databaseType: DatabaseType.sqlServer,
        scheduleType: 'daily',
      ),
      _sampleSchedule(
        id: '2',
        name: 'Firebird Weekly',
        databaseType: DatabaseType.firebird,
        scheduleType: 'weekly',
        enabled: false,
      ),
    ],
    onEdit: (_) {},
    onDuplicate: (_) {},
    onDelete: (_) {},
    onRunNow: (_) {},
    onToggleEnabled: (schedule, enabled) {},
  );
}
