import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_serializers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseConfigSerializers — Sybase', () {
    test('round-trip preserva campos chave', () {
      final original = SybaseConfig(
        id: 'cfg-1',
        name: 'Producao',
        serverName: 'srv-prod',
        databaseName: DatabaseName('app'),
        databaseFile: 'app.db',
        port: PortNumber(2638),
        username: 'sa',
        password: 'secret',
        isReplicationEnvironment: true,
      );
      final map = DatabaseConfigSerializers.sybaseToMap(
        original,
        includePassword: true,
      );
      final restored = DatabaseConfigSerializers.sybaseFromMap(map);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.serverName, original.serverName);
      expect(restored.databaseNameValue, original.databaseNameValue);
      expect(restored.databaseFile, original.databaseFile);
      expect(restored.portValue, original.portValue);
      expect(restored.username, original.username);
      expect(restored.password, original.password);
      expect(restored.isReplicationEnvironment, isTrue);
    });

    test('toMap NAO inclui password por default (seguranca)', () {
      final cfg = SybaseConfig(
        id: 'x',
        name: 'n',
        serverName: 's',
        databaseName: DatabaseName('d'),
        username: 'u',
        password: 'SENHA-SECRETA',
      );
      final map = DatabaseConfigSerializers.sybaseToMap(cfg);
      expect(map.containsKey('password'), isFalse);
      expect(map['username'], 'u');
    });

    test('fromMap aceita port como string ou int', () {
      final map = <String, dynamic>{
        'name': 'n',
        'serverName': 's',
        'databaseName': 'd',
        'username': 'u',
        'port': '1234', // string
      };
      final cfg = DatabaseConfigSerializers.sybaseFromMap(map);
      expect(cfg.portValue, 1234);
    });

    test('fromMap usa default port quando ausente', () {
      final cfg = DatabaseConfigSerializers.sybaseFromMap(
        const {
          'name': 'n',
          'serverName': 's',
          'databaseName': 'd',
          'username': 'u',
        },
      );
      expect(cfg.portValue, 2638);
    });

    test('fromMap rejeita campos obrigatorios faltando', () {
      expect(
        () => DatabaseConfigSerializers.sybaseFromMap(
          const <String, dynamic>{'serverName': 's'},
        ),
        throwsArgumentError,
      );
    });
  });

  group('DatabaseConfigSerializers — SqlServer', () {
    test('round-trip', () {
      final original = SqlServerConfig(
        id: 'sql-1',
        name: 'sql prod',
        server: 'localhost',
        database: DatabaseName('app'),
        username: 'sa',
        password: 'p',
        port: PortNumber(1433),
        useWindowsAuth: true,
      );
      final map = DatabaseConfigSerializers.sqlServerToMap(
        original,
        includePassword: true,
      );
      final restored = DatabaseConfigSerializers.sqlServerFromMap(map);
      expect(restored.id, original.id);
      expect(restored.server, original.server);
      expect(restored.databaseValue, original.databaseValue);
      expect(restored.useWindowsAuth, isTrue);
    });

    test('default port 1433 quando ausente', () {
      final cfg = DatabaseConfigSerializers.sqlServerFromMap(
        const {
          'name': 'n',
          'server': 's',
          'database': 'd',
        },
      );
      expect(cfg.portValue, 1433);
    });
  });

  group('DatabaseConfigSerializers — Postgres', () {
    test('round-trip', () {
      final original = PostgresConfig(
        id: 'pg-1',
        name: 'pg prod',
        host: 'localhost',
        database: DatabaseName('app'),
        username: 'postgres',
        password: 'p',
        port: PortNumber(5432),
      );
      final map = DatabaseConfigSerializers.postgresToMap(
        original,
        includePassword: true,
      );
      final restored = DatabaseConfigSerializers.postgresFromMap(map);
      expect(restored.id, original.id);
      expect(restored.host, original.host);
      expect(restored.databaseValue, original.databaseValue);
      expect(restored.portValue, 5432);
    });

    test('default port 5432 quando ausente', () {
      final cfg = DatabaseConfigSerializers.postgresFromMap(
        const {
          'name': 'n',
          'host': 'h',
          'database': 'd',
          'username': 'u',
        },
      );
      expect(cfg.portValue, 5432);
    });
  });
}
