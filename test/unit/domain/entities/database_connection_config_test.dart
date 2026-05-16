import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';

String readHost(DatabaseConnectionConfig config) => config.host;

DatabaseType readType(DatabaseConnectionConfig config) => config.databaseType;

String readPrimaryDbName(DatabaseConnectionConfig config) =>
    config.primaryDatabase.value;

void main() {
  group('DatabaseConnectionConfig LSP', () {
    test('SqlServerConfig exposes unified view', () {
      final sql = SqlServerConfig(
        name: 'n',
        server: 'sql-host',
        database: DatabaseName('db1'),
        username: 'u',
        password: 'p',
      );

      final DatabaseConnectionConfig asBase = sql;
      expect(asBase, same(sql));
      expect(readHost(asBase), 'sql-host');
      expect(readType(asBase), DatabaseType.sqlServer);
      expect(readPrimaryDbName(asBase), 'db1');
      expect(asBase.backupTarget, isNull);
      expect(asBase.portValue, 1433);
    });

    test('PostgresConfig exposes unified view', () {
      final pg = PostgresConfig(
        name: 'n',
        host: 'pg-host',
        database: DatabaseName('db2'),
        username: 'u',
        password: 'p',
        port: PortNumber(5433),
      );

      final DatabaseConnectionConfig asBase = pg;
      expect(readHost(asBase), 'pg-host');
      expect(readType(asBase), DatabaseType.postgresql);
      expect(readPrimaryDbName(asBase), 'db2');
      expect(asBase.backupTarget, isNull);
      expect(asBase.portValue, 5433);
    });

    test('SybaseConfig exposes unified view', () {
      final sy = SybaseConfig(
        name: 'n',
        serverName: 'syb-engine',
        databaseName: DatabaseName('db3'),
        username: 'u',
        password: 'p',
      );

      final DatabaseConnectionConfig asBase = sy;
      expect(readHost(asBase), 'syb-engine');
      expect(readType(asBase), DatabaseType.sybase);
      expect(readPrimaryDbName(asBase), 'db3');
      expect(asBase.backupTarget, isNull);
      expect(asBase.portValue, 2638);
    });
  });
}
