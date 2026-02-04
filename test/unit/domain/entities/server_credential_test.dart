import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerCredential', () {
    final createdAt = DateTime(2025, 1, 1, 12);
    const id = 'id-1';
    const serverId = 'server-1';
    const passwordHash = 'hash';
    const name = 'Credential 1';

    test('should be equal when ids are the same', () {
      final a = ServerCredential(
        id: id,
        serverId: serverId,
        passwordHash: passwordHash,
        name: name,
        isActive: true,
        createdAt: createdAt,
      );
      final b = ServerCredential(
        id: id,
        serverId: 'other',
        passwordHash: 'other',
        name: 'Other',
        isActive: false,
        createdAt: DateTime(2020),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('should not be equal when ids are different', () {
      final a = ServerCredential(
        id: 'id-a',
        serverId: serverId,
        passwordHash: passwordHash,
        name: name,
        isActive: true,
        createdAt: createdAt,
      );
      final b = ServerCredential(
        id: 'id-b',
        serverId: serverId,
        passwordHash: passwordHash,
        name: name,
        isActive: true,
        createdAt: createdAt,
      );
      expect(a, isNot(equals(b)));
    });

    test('copyWith should preserve unchanged fields and update given ones', () {
      final credential = ServerCredential(
        id: id,
        serverId: serverId,
        passwordHash: passwordHash,
        name: name,
        isActive: true,
        createdAt: createdAt,
        lastUsedAt: DateTime(2025, 1, 2),
        description: 'desc',
      );
      final updated = credential.copyWith(name: 'New Name', isActive: false);
      expect(updated.id, id);
      expect(updated.serverId, serverId);
      expect(updated.name, 'New Name');
      expect(updated.isActive, isFalse);
      expect(updated.lastUsedAt, DateTime(2025, 1, 2));
      expect(updated.description, 'desc');
    });
  });
}
