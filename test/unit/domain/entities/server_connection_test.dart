import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerConnection', () {
    final createdAt = DateTime(2025, 1, 1, 12);
    final updatedAt = DateTime(2025, 1, 2, 12);
    const id = 'id-1';
    const name = 'My Server';
    const serverId = 'server-1';
    const host = '127.0.0.1';
    const port = 9527;
    const password = 'secret';

    test('should be equal when ids are the same', () {
      final a = ServerConnection(
        id: id,
        name: name,
        serverId: serverId,
        host: host,
        port: port,
        password: password,
        isOnline: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      final b = ServerConnection(
        id: id,
        name: 'Other',
        serverId: 'other',
        host: '0.0.0.0',
        port: 8080,
        password: 'other',
        isOnline: true,
        createdAt: DateTime(2020),
        updatedAt: DateTime(2020),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('should not be equal when ids are different', () {
      final a = ServerConnection(
        id: 'id-a',
        name: name,
        serverId: serverId,
        host: host,
        port: port,
        password: password,
        isOnline: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      final b = ServerConnection(
        id: 'id-b',
        name: name,
        serverId: serverId,
        host: host,
        port: port,
        password: password,
        isOnline: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      expect(a, isNot(equals(b)));
    });

    test('copyWith should preserve unchanged fields and update given ones', () {
      final connection = ServerConnection(
        id: id,
        name: name,
        serverId: serverId,
        host: host,
        port: port,
        password: password,
        isOnline: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastConnectedAt: DateTime(2025, 1, 3),
      );
      final updated = connection.copyWith(name: 'New Name', port: 9530);
      expect(updated.id, id);
      expect(updated.name, 'New Name');
      expect(updated.port, 9530);
      expect(updated.lastConnectedAt, DateTime(2025, 1, 3));
    });
  });
}
