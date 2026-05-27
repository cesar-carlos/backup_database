import 'package:backup_database/application/providers/database_connection_test_snapshot.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
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
      rowOf: _rowOf,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      onToggleEnabled: onToggleEnabled,
      onAddWhenEmpty: onAddWhenEmpty,
      addWhenEmptyButtonLabel: addWhenEmptyButtonLabel,
      connectionTestSnapshot: connectionTestSnapshot,
    );
  }

  static DatabaseConfigGridRow _rowOf(FirebirdConfig c) {
    // Em modo embedded o host/port nao tem significado (nao ha
    // conexao TCP), e o "database" e o caminho do .fdb local. Em
    // alias-only (databaseFile vazio), mostrar o alias evita celula
    // em branco que confunde o utilizador.
    final endpoint = c.useEmbedded
        ? '(embedded)'
        : '${c.host}:${c.portValue}';
    final database = c.databaseFile.isNotEmpty
        ? c.databaseFile
        : (c.aliasName?.trim() ?? '');
    return DatabaseConfigGridRow(
      databaseType: DatabaseType.firebird,
      name: c.name,
      serverEndpoint: endpoint,
      database: database,
      username: c.username,
      id: c.id,
      enabled: c.enabled,
    );
  }
}
