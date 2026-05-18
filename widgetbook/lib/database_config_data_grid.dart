import 'package:backup_database/presentation/widgets/organisms/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

final class _StoryConfig {
  const _StoryConfig({
    required this.id,
    required this.name,
    required this.serverEndpoint,
    required this.database,
    required this.username,
    required this.enabled,
  });

  final String id;
  final String name;
  final String serverEndpoint;
  final String database;
  final String username;
  final bool enabled;
}

List<_StoryConfig> get _sampleRows => const [
  _StoryConfig(
    id: '1',
    name: 'Production SQL',
    serverEndpoint: 'sql01.corp.local\\INSTANCE01',
    database: 'ERP_MAIN',
    username: 'backup_svc',
    enabled: true,
  ),
  _StoryConfig(
    id: '2',
    name: 'Reporting',
    serverEndpoint: 'sql02.corp.local',
    database: 'DWarehouse',
    username: 'readonly',
    enabled: false,
  ),
  _StoryConfig(
    id: '3',
    name: 'Dev',
    serverEndpoint: 'localhost',
    database: 'Sandbox',
    username: 'sa',
    enabled: true,
  ),
];

DatabaseConfigGridRow _rowOf(_StoryConfig row) {
  return DatabaseConfigGridRow(
    name: row.name,
    serverEndpoint: row.serverEndpoint,
    database: row.database,
    username: row.username,
    id: row.id,
    enabled: row.enabled,
  );
}

@widgetbook.UseCase(name: 'With rows', type: DatabaseConfigDataGrid)
Widget buildDatabaseConfigDataGridWithRowsUseCase(BuildContext context) {
  return _gridScroll(
    DatabaseConfigDataGrid<_StoryConfig>(
      configs: _sampleRows,
      rowOf: _rowOf,
      minWidth: 1100,
      onEdit: (_) {},
      onDuplicate: (_) {},
      onDelete: (_) {},
      onToggleEnabled: (String id, bool enabled) {},
    ),
  );
}

@widgetbook.UseCase(name: 'With last test column', type: DatabaseConfigDataGrid)
Widget buildDatabaseConfigDataGridWithTestColumnUseCase(BuildContext context) {
  return _gridScroll(
    DatabaseConfigDataGrid<_StoryConfig>(
      configs: _sampleRows,
      rowOf: _rowOf,
      minWidth: 1200,
      onEdit: (_) {},
      onDuplicate: (_) {},
      onDelete: (_) {},
      onToggleEnabled: (String id, bool enabled) {},
      connectionTestSnapshot: (String id) {
        if (id == '1') {
          return (testedAt: DateTime(2026, 5, 18, 9, 30), success: true);
        }
        if (id == '2') {
          return (testedAt: DateTime(2026, 5, 17, 14, 12), success: false);
        }
        return null;
      },
    ),
  );
}

@widgetbook.UseCase(name: 'Empty', type: DatabaseConfigDataGrid)
Widget buildDatabaseConfigDataGridEmptyUseCase(BuildContext context) {
  return _gridScroll(
    DatabaseConfigDataGrid<_StoryConfig>(configs: const [], rowOf: _rowOf),
  );
}

@widgetbook.UseCase(name: 'Empty with add', type: DatabaseConfigDataGrid)
Widget buildDatabaseConfigDataGridEmptyWithAddUseCase(BuildContext context) {
  return _gridScroll(
    DatabaseConfigDataGrid<_StoryConfig>(
      configs: const [],
      rowOf: _rowOf,
      onAddWhenEmpty: () {},
      addWhenEmptyButtonLabel: 'New configuration',
    ),
  );
}

Widget _gridScroll(Widget grid) {
  return Align(
    alignment: Alignment.topLeft,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(padding: const EdgeInsets.only(bottom: 16), child: grid),
    ),
  );
}
