import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

BackupDestination _sampleDestination({
  required String id,
  required String name,
  required DestinationType type,
  required String config,
  bool enabled = true,
}) {
  return BackupDestination(
    id: id,
    name: name,
    type: type,
    config: config,
    enabled: enabled,
  );
}

@widgetbook.UseCase(name: 'Default', type: DestinationGrid)
Widget buildDestinationGridUseCase(BuildContext context) {
  return DestinationGrid(
    destinations: [
      _sampleDestination(
        id: '1',
        name: 'Local NAS',
        type: DestinationType.local,
        config: '{"path":"D:/Backups"}',
      ),
      _sampleDestination(
        id: '2',
        name: 'FTP Mirror',
        type: DestinationType.ftp,
        config: '{"host":"ftp.example.com","remotePath":"/daily"}',
        enabled: false,
      ),
    ],
    onEdit: (_) {},
    onDuplicate: (_) {},
    onDelete: (_) {},
    onToggleEnabled: (destination, enabled) {},
  );
}
