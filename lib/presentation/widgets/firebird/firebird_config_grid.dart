import 'package:backup_database/application/providers/database_connection_test_snapshot.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/presentation/widgets/organisms/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';

class FirebirdConfigGrid extends StatelessWidget {
  const FirebirdConfigGrid({
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

  final List<FirebirdConfig> configs;
  final void Function(FirebirdConfig)? onEdit;
  final void Function(FirebirdConfig)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;
  final VoidCallback? onAddWhenEmpty;
  final String? addWhenEmptyButtonLabel;
  final DatabaseConnectionTestSnapshot? Function(String configId)?
  connectionTestSnapshot;

  @override
  Widget build(BuildContext context) {
    return DatabaseConfigDataGrid<FirebirdConfig>(
      configs: configs,
      rowOf: (FirebirdConfig c) => DatabaseConfigGridRow(
        name: c.name,
        serverEndpoint: '${c.host}:${c.portValue}',
        database: c.databaseFile,
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
