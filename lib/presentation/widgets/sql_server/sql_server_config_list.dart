import 'package:backup_database/application/providers/database_connection_test_snapshot.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/presentation/widgets/organisms/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SqlServerConfigList extends StatelessWidget {
  const SqlServerConfigList({
    required this.configs,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
    this.onAddWhenEmpty,
    this.addWhenEmptyButtonLabel,
    this.connectionTestSnapshot,
  });
  final List<SqlServerConfig> configs;
  final void Function(SqlServerConfig)? onEdit;
  final void Function(SqlServerConfig)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;
  final VoidCallback? onAddWhenEmpty;
  final String? addWhenEmptyButtonLabel;
  final DatabaseConnectionTestSnapshot? Function(String configId)?
  connectionTestSnapshot;

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
      onAddWhenEmpty: onAddWhenEmpty,
      addWhenEmptyButtonLabel: addWhenEmptyButtonLabel,
      connectionTestSnapshot: connectionTestSnapshot,
    );
  }
}
