import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/common/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DatabaseConfigDataGrid shows empty state when list empty', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        home: ScaffoldPage(
          content: DatabaseConfigDataGrid<SqlServerConfig>(
            configs: [],
            rowOf: _neverSql,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No configuration found'), findsOneWidget);
  });

  testWidgets('DatabaseConfigDataGrid renders SqlServerConfig row', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cfg = SqlServerConfig(
      id: 'id-sql',
      name: 'Alpha',
      server: 'srv1',
      database: DatabaseName('db1'),
      username: 'u1',
      password: 'p',
      port: PortNumber(1433),
    );

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: DatabaseConfigDataGrid<SqlServerConfig>(
            configs: [cfg],
            rowOf: (c) => DatabaseConfigGridRow(
              name: c.name,
              serverEndpoint: '${c.server}:${c.portValue}',
              database: c.databaseValue,
              username: c.username,
              id: c.id,
              enabled: c.enabled,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('srv1:1433'), findsOneWidget);
    expect(find.text('db1'), findsOneWidget);
    expect(find.text('u1'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('DatabaseConfigDataGrid renders SybaseConfig row', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cfg = SybaseConfig(
      id: 'id-syb',
      name: 'Beta',
      serverName: 'syb1',
      databaseName: DatabaseName('db2'),
      username: 'u2',
      password: 'p',
      port: PortNumber(2638),
    );

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: DatabaseConfigDataGrid<SybaseConfig>(
            configs: [cfg],
            rowOf: (c) => DatabaseConfigGridRow(
              name: c.name,
              serverEndpoint: '${c.serverName}:${c.portValue}',
              database: c.databaseNameValue,
              username: c.username,
              id: c.id,
              enabled: c.enabled,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('syb1:2638'), findsOneWidget);
    expect(find.text('db2'), findsOneWidget);
  });

  testWidgets('DatabaseConfigDataGrid renders PostgresConfig row', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cfg = PostgresConfig(
      id: 'id-pg',
      name: 'Gamma',
      host: 'pg1',
      database: DatabaseName('db3'),
      username: 'u3',
      password: 'p',
      port: PortNumber(5432),
    );

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: DatabaseConfigDataGrid<PostgresConfig>(
            configs: [cfg],
            rowOf: (c) => DatabaseConfigGridRow(
              name: c.name,
              serverEndpoint: '${c.host}:${c.portValue}',
              database: c.databaseValue,
              username: c.username,
              id: c.id,
              enabled: c.enabled,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('pg1:5432'), findsOneWidget);
    expect(find.text('db3'), findsOneWidget);
  });
}

DatabaseConfigGridRow _neverSql(SqlServerConfig c) =>
    throw StateError('unreachable');
