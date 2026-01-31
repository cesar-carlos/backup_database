import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SqlServerConfig', () {
    test('deve criar instância com valores padrão', () {
      final config = SqlServerConfig(
        name: 'Test',
        server: 'localhost',
        database: 'TestDB',
        username: 'sa',
        password: 'password',
      );

      expect(config.name, 'Test');
      expect(config.server, 'localhost');
      expect(config.port, 1433);
      expect(config.enabled, true);
      expect(config.id, isNotEmpty);
    });

    test('deve criar cópia com valores alterados', () {
      final config = SqlServerConfig(
        name: 'Test',
        server: 'localhost',
        database: 'TestDB',
        username: 'sa',
        password: 'password',
      );

      final copy = config.copyWith(name: 'New Name', port: 1434);

      expect(copy.name, 'New Name');
      expect(copy.port, 1434);
      expect(copy.server, 'localhost');
      expect(copy.id, config.id);
    });

    test('deve comparar por id', () {
      final config1 = SqlServerConfig(
        id: 'same-id',
        name: 'Test1',
        server: 'localhost',
        database: 'TestDB',
        username: 'sa',
        password: 'password',
      );

      final config2 = SqlServerConfig(
        id: 'same-id',
        name: 'Test2',
        server: 'other',
        database: 'OtherDB',
        username: 'user',
        password: 'other',
      );

      expect(config1, equals(config2));
      expect(config1.hashCode, equals(config2.hashCode));
    });
  });
}
