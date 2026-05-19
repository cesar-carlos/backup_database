import 'package:backup_database/application/providers/database_connection_test_snapshot.dart';
import 'package:backup_database/core/theme/tokens/app_density.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:backup_database/presentation/widgets/organisms/database_config_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _densityHarness(Widget home) {
  return InheritedAppDensity(
    density: AppDensity.comfortable,
    child: home,
  );
}

void main() {
  testWidgets('DatabaseConfigDataGrid shows empty state when list empty', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: _densityHarness(
          const ScaffoldPage(
            content: DatabaseConfigDataGrid<SqlServerConfig>(
              configs: [],
              rowOf: _neverSql,
            ),
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
        home: _densityHarness(
          ScaffoldPage(
            content: DatabaseConfigDataGrid<SqlServerConfig>(
              configs: [cfg],
              rowOf: (c) => DatabaseConfigGridRow(
                databaseType: DatabaseType.sqlServer,
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
      ),
    );
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('srv1:1433'), findsOneWidget);
    expect(find.text('db1'), findsOneWidget);
    expect(find.text('u1'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('SQL Server'), findsOneWidget);
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
        home: _densityHarness(
          ScaffoldPage(
            content: DatabaseConfigDataGrid<SybaseConfig>(
              configs: [cfg],
              rowOf: (c) => DatabaseConfigGridRow(
                databaseType: DatabaseType.sybase,
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
      ),
    );
    await tester.pump();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('syb1:2638'), findsOneWidget);
    expect(find.text('db2'), findsOneWidget);
    expect(find.text('Sybase'), findsOneWidget);
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
        home: _densityHarness(
          ScaffoldPage(
            content: DatabaseConfigDataGrid<PostgresConfig>(
              configs: [cfg],
              rowOf: (c) => DatabaseConfigGridRow(
                databaseType: DatabaseType.postgresql,
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
      ),
    );
    await tester.pump();
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('pg1:5432'), findsOneWidget);
    expect(find.text('db3'), findsOneWidget);
    expect(find.text('PostgreSQL'), findsOneWidget);
  });

  testWidgets(
    'DatabaseConfigDataGrid shows Last check when snapshot provided',
    (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cfg = SqlServerConfig(
        id: 'id-snap',
        name: 'Snap',
        server: 'srv',
        database: DatabaseName('db'),
        username: 'u',
        password: 'p',
        port: PortNumber(1433),
      );

      DatabaseConnectionTestSnapshot? snapshotFor(String id) {
        if (id != 'id-snap') {
          return null;
        }
        return (testedAt: DateTime.utc(2026, 5, 15, 12, 30), success: true);
      }

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('en'),
          home: _densityHarness(
            ScaffoldPage(
              content: DatabaseConfigDataGrid<SqlServerConfig>(
                configs: [cfg],
                connectionTestSnapshot: snapshotFor,
                rowOf: (c) => DatabaseConfigGridRow(
                  databaseType: DatabaseType.sqlServer,
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
        ),
      );
      await tester.pump();
      expect(find.text('Last check'), findsOneWidget);
      expect(find.text('Never'), findsNothing);
    },
  );
}

DatabaseConfigGridRow _neverSql(SqlServerConfig c) =>
    throw StateError('unreachable');
