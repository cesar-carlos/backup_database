import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SqlServerConfig', () {
    test('deve criar instância com valores padrão', () {
      final config = SqlServerConfig(
        name: 'Test',
        server: 'localhost',
        database: DatabaseName('TestDB'),
        username: 'sa',
        password: 'password',
      );

      expect(config.name, 'Test');
      expect(config.server, 'localhost');
      expect(config.portValue, 1433);
      expect(config.enabled, true);
      expect(config.id, isNotEmpty);
    });

    test('deve criar cópia com valores alterados', () {
      final config = SqlServerConfig(
        name: 'Test',
        server: 'localhost',
        database: DatabaseName('TestDB'),
        username: 'sa',
        password: 'password',
      );

      final copy = config.copyWith(name: 'New Name', port: PortNumber(1434));

      expect(copy.name, 'New Name');
      expect(copy.portValue, 1434);
      expect(copy.server, 'localhost');
      expect(copy.id, config.id);
    });

    test('deve comparar por id', () {
      final config1 = SqlServerConfig(
        id: 'same-id',
        name: 'Test1',
        server: 'localhost',
        database: DatabaseName('TestDB'),
        username: 'sa',
        password: 'password',
      );

      final config2 = SqlServerConfig(
        id: 'same-id',
        name: 'Test2',
        server: 'other',
        database: DatabaseName('OtherDB'),
        username: 'user',
        password: 'other',
      );

      expect(config1, equals(config2));
      expect(config1.hashCode, equals(config2.hashCode));
    });
  });
}
