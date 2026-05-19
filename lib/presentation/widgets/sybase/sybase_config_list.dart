import 'package:backup_database/application/providers/database_connection_test_snapshot.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/presentation/widgets/organisms/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SybaseConfigList extends StatelessWidget {
  const SybaseConfigList({
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
  final List<SybaseConfig> configs;
  final void Function(SybaseConfig)? onEdit;
  final void Function(SybaseConfig)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;
  final VoidCallback? onAddWhenEmpty;
  final String? addWhenEmptyButtonLabel;
  final DatabaseConnectionTestSnapshot? Function(String configId)?
  connectionTestSnapshot;

  @override
  Widget build(BuildContext context) {
    return DatabaseConfigDataGrid<SybaseConfig>(
      configs: configs,
      rowOf: (c) => DatabaseConfigGridRow(
        databaseType: DatabaseType.sybase,
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
      onAddWhenEmpty: onAddWhenEmpty,
      addWhenEmptyButtonLabel: addWhenEmptyButtonLabel,
      connectionTestSnapshot: connectionTestSnapshot,
    );
  }
}
