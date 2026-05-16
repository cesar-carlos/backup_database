import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/presentation/widgets/common/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SqlServerConfigList extends StatelessWidget {
  const SqlServerConfigList({
    required this.configs,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });
  final List<SqlServerConfig> configs;
  final void Function(SqlServerConfig)? onEdit;
  final void Function(SqlServerConfig)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return DatabaseConfigDataGrid<SqlServerConfig>(
      configs: configs,
      rowOf: (c) => DatabaseConfigGridRow(
        name: c.name,
        serverEndpoint: '${c.server}:${c.portValue}',
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
