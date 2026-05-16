import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/presentation/widgets/common/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PostgresConfigGrid extends StatelessWidget {
  const PostgresConfigGrid({
    required this.configs,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });

  final List<PostgresConfig> configs;
  final void Function(PostgresConfig)? onEdit;
  final void Function(PostgresConfig)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return DatabaseConfigDataGrid<PostgresConfig>(
      configs: configs,
      rowOf: (c) => DatabaseConfigGridRow(
        name: c.name,
        serverEndpoint: '${c.host}:${c.portValue}',
        database: c.databaseValue,
        username: c.username,
        id: c.id,
        enabled: c.enabled,
      ),
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      onToggleEnabled: onToggleEnabled,
    );
  }
}
