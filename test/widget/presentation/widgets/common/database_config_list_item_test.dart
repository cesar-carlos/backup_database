import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/presentation/widgets/molecules/database_config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DatabaseConfigListItem uses DatabaseTypeMetadata accent (SQL)', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cfg = SqlServerConfig(
      id: '1',
      name: 'CfgSql',
      server: 's1',
      database: DatabaseName('d1'),
      username: 'u1',
      password: 'p',
    );

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: DatabaseConfigListItem<SqlServerConfig>(
            config: cfg,
            name: cfg.name,
            enabled: cfg.enabled,
            databaseType: DatabaseType.sqlServer,
            subtitle: (context, c) => Text(c.server),
          ),
        ),
      ),
    );
    await tester.pump();

    final icon =
        tester.widget(
              find.descendant(
                of: find.byType(CircleAvatar),
                matching: find.byType(Icon),
              ),
            )
            as Icon;
    expect(
      icon.color,
      DatabaseTypeMetadata.of(DatabaseType.sqlServer).accentColor,
    );
    expect(find.text('CfgSql'), findsOneWidget);
  });

  testWidgets(
    'DatabaseConfigListItem uses DatabaseTypeMetadata accent (Sybase)',
    (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(480, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cfg = SybaseConfig(
        id: '2',
        name: 'CfgSyb',
        serverName: 'sy1',
        databaseName: DatabaseName('d2'),
        username: 'u2',
        password: 'p',
      );

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('en'),
          home: ScaffoldPage(
            content: DatabaseConfigListItem<SybaseConfig>(
              config: cfg,
              name: cfg.name,
              enabled: cfg.enabled,
              databaseType: DatabaseType.sybase,
              subtitle: (context, c) => Text(c.serverName),
            ),
          ),
        ),
      );
      await tester.pump();

      final icon =
          tester.widget(
                find.descendant(
                  of: find.byType(CircleAvatar),
                  matching: find.byType(Icon),
                ),
              )
              as Icon;
      expect(
        icon.color,
        DatabaseTypeMetadata.of(DatabaseType.sybase).accentColor,
      );
    },
  );

  testWidgets(
    'DatabaseConfigListItem uses DatabaseTypeMetadata accent (Postgres)',
    (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(480, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cfg = PostgresConfig(
        id: '3',
        name: 'CfgPg',
        host: 'h1',
        database: DatabaseName('d3'),
        username: 'u3',
        password: 'p',
      );

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('en'),
          home: ScaffoldPage(
            content: DatabaseConfigListItem<PostgresConfig>(
              config: cfg,
              name: cfg.name,
              enabled: cfg.enabled,
              databaseType: DatabaseType.postgresql,
              subtitle: (context, c) => Text(c.host),
            ),
          ),
        ),
      );
      await tester.pump();

      final icon =
          tester.widget(
                find.descendant(
                  of: find.byType(CircleAvatar),
                  matching: find.byType(Icon),
                ),
              )
              as Icon;
      expect(
        icon.color,
        DatabaseTypeMetadata.of(DatabaseType.postgresql).accentColor,
      );
    },
  );
}
