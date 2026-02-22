import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/server_connection_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late ServerConnectionRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = ServerConnectionRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('ServerConnectionRepository', () {
    final createdAt = DateTime(2025, 1, 1, 12);
    final updatedAt = DateTime(2025, 1, 2, 12);

    ServerConnection connection({
      String id = 'id-1',
      String name = 'My Server',
      String host = '127.0.0.1',
      int port = 9527,
    }) {
      return ServerConnection(
        id: id,
        name: name,
        serverId: 'server-1',
        host: host,
        port: port,
        password: 'pwd',
        isOnline: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    test('getAll should return empty list when no connections', () async {
      final result = await repository.getAll();
      expect(result.isSuccess(), isTrue);
      result.fold(
        (list) => expect(list, isEmpty),
        (_) => fail('Should not fail'),
      );
    });

    test('save then getAll should return the connection', () async {
      final c = connection();
      final saveResult = await repository.save(c);
      expect(saveResult.isSuccess(), isTrue);

      final getAllResult = await repository.getAll();
      expect(getAllResult.isSuccess(), isTrue);
      getAllResult.fold(
        (list) {
          expect(list.length, 1);
          expect(list.first.id, c.id);
          expect(list.first.host, c.host);
          expect(list.first.port, c.port);
        },
        (_) => fail('Should not fail'),
      );
    });

    test('getById should return connection after save', () async {
      final c = connection();
      await repository.save(c);

      final result = await repository.getById(c.id);
      expect(result.isSuccess(), isTrue);
      result.fold(
        (found) {
          expect(found.id, c.id);
          expect(found.serverId, c.serverId);
        },
        (_) => fail('Should not fail'),
      );
    });

    test(
      'getById should return NotFoundFailure when id does not exist',
      () async {
        final result = await repository.getById('non-existent');
        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Should not succeed'),
          (f) {
            expect(f, isA<Failure>());
            expect((f as Failure).message, contains('não encontrada'));
          },
        );
      },
    );

    test('update should persist changes', () async {
      final c = connection();
      await repository.save(c);
      final updated = c.copyWith(name: 'Updated Name', port: 9530);

      final updateResult = await repository.update(updated);
      expect(updateResult.isSuccess(), isTrue);

      final getResult = await repository.getById(c.id);
      getResult.fold(
        (found) {
          expect(found.name, 'Updated Name');
          expect(found.port, 9530);
        },
        (_) => fail('Should not fail'),
      );
    });

    test('delete should remove connection', () async {
      final c = connection();
      await repository.save(c);

      final deleteResult = await repository.delete(c.id);
      expect(deleteResult.isSuccess(), isTrue);

      final getResult = await repository.getById(c.id);
      expect(getResult.isError(), isTrue);
    });

    test('watchAll should emit list when connections change', () async {
      final c = connection();
      final emissions = <List<ServerConnection>>[];
      final sub = repository.watchAll().listen(emissions.add);

      await repository.save(c);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions, isNotEmpty);
      expect(emissions.last.length, 1);
      expect(emissions.last.first.id, c.id);

      await sub.cancel();
    });
  });
}
