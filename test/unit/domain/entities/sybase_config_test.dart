import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SybaseConfig', () {
    test('should create instance with default port and enabled', () {
      final config = SybaseConfig(
        name: 'Test',
        serverName: 'localhost',
        databaseName: DatabaseName('db1'),
        username: 'dba',
        password: 'password',
      );

      expect(config.name, 'Test');
      expect(config.serverName, 'localhost');
      expect(config.portValue, 2638);
      expect(config.enabled, isTrue);
      expect(config.id, isNotEmpty);
    });

    test('should create copy with changed fields', () {
      final config = SybaseConfig(
        name: 'Test',
        serverName: 'localhost',
        databaseName: DatabaseName('db1'),
        username: 'dba',
        password: 'password',
      );

      final copy = config.copyWith(name: 'New Name', port: PortNumber(2639));

      expect(copy.name, 'New Name');
      expect(copy.portValue, 2639);
      expect(copy.serverName, 'localhost');
      expect(copy.id, config.id);
    });

    test('should compare by id', () {
      final config1 = SybaseConfig(
        id: 'same-id',
        name: 'Test1',
        serverName: 'localhost',
        databaseName: DatabaseName('db1'),
        username: 'dba',
        password: 'password',
      );

      final config2 = SybaseConfig(
        id: 'same-id',
        name: 'Test2',
        serverName: 'other',
        databaseName: DatabaseName('other'),
        username: 'user',
        password: 'other',
      );

      expect(config1, equals(config2));
      expect(config1.hashCode, equals(config2.hashCode));
    });
  });
}
