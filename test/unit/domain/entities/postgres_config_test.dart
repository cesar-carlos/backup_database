import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostgresConfig', () {
    test('should create instance with default port and enabled', () {
      final config = PostgresConfig(
        name: 'Test',
        host: 'localhost',
        database: DatabaseName('db1'),
        username: 'pg',
        password: 'password',
      );

      expect(config.name, 'Test');
      expect(config.host, 'localhost');
      expect(config.portValue, 5432);
      expect(config.enabled, isTrue);
      expect(config.id, isNotEmpty);
    });

    test('should create copy with changed fields', () {
      final config = PostgresConfig(
        name: 'Test',
        host: 'localhost',
        database: DatabaseName('db1'),
        username: 'pg',
        password: 'password',
      );

      final copy = config.copyWith(name: 'New Name', port: PortNumber(5433));

      expect(copy.name, 'New Name');
      expect(copy.portValue, 5433);
      expect(copy.host, 'localhost');
      expect(copy.id, config.id);
    });

    test('should compare by id', () {
      final config1 = PostgresConfig(
        id: 'same-id',
        name: 'Test1',
        host: 'localhost',
        database: DatabaseName('db1'),
        username: 'pg',
        password: 'password',
      );

      final config2 = PostgresConfig(
        id: 'same-id',
        name: 'Test2',
        host: 'other',
        database: DatabaseName('other'),
        username: 'user',
        password: 'other',
      );

      expect(config1, equals(config2));
      expect(config1.hashCode, equals(config2.hashCode));
    });
  });
}
