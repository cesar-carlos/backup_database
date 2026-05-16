import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/presentation/widgets/common/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SybaseConfigList extends StatelessWidget {
  const SybaseConfigList({
    required this.configs,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });
  final List<SybaseConfig> configs;
  final void Function(SybaseConfig)? onEdit;
  final void Function(SybaseConfig)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return DatabaseConfigDataGrid<SybaseConfig>(
      configs: configs,
      rowOf: (c) => DatabaseConfigGridRow(
        name: c.name,
        serverEndpoint: '${c.serverName}:${c.portValue}',
        database: c.databaseNameValue,
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
