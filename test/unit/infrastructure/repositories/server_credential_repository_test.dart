import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/server_credential_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late ServerCredentialRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = ServerCredentialRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('ServerCredentialRepository', () {
    final createdAt = DateTime(2025, 1, 1, 12);

    ServerCredential credential({
      String id = 'id-1',
      String serverId = 'server-1',
      String name = 'Credential 1',
    }) {
      return ServerCredential(
        id: id,
        serverId: serverId,
        passwordHash: 'hash',
        name: name,
        isActive: true,
        createdAt: createdAt,
      );
    }

    test('getAll should return empty list when no credentials', () async {
      final result = await repository.getAll();
      expect(result.isSuccess(), isTrue);
      result.fold(
        (list) => expect(list, isEmpty),
        (_) => fail('Should not fail'),
      );
    });

    test('save then getAll should return the credential', () async {
      final c = credential();
      final saveResult = await repository.save(c);
      expect(saveResult.isSuccess(), isTrue);

      final getAllResult = await repository.getAll();
      expect(getAllResult.isSuccess(), isTrue);
      getAllResult.fold(
        (list) {
          expect(list.length, 1);
          expect(list.first.id, c.id);
          expect(list.first.serverId, c.serverId);
          expect(list.first.name, c.name);
        },
        (_) => fail('Should not fail'),
      );
    });

    test('getById should return credential after save', () async {
      final c = credential();
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

    test('getByServerId should return credential after save', () async {
      final c = credential(serverId: 'my-server');
      await repository.save(c);

      final result = await repository.getByServerId('my-server');
      expect(result.isSuccess(), isTrue);
      result.fold(
        (found) {
          expect(found.serverId, 'my-server');
        },
        (_) => fail('Should not fail'),
      );
    });

    test(
      'getByServerId should return NotFoundFailure when serverId does not exist',
      () async {
        final result = await repository.getByServerId('no-such-server');
        expect(result.isError(), isTrue);
      },
    );

    test('update should persist changes', () async {
      final c = credential();
      await repository.save(c);
      final updated = c.copyWith(name: 'Updated Name', isActive: false);

      final updateResult = await repository.update(updated);
      expect(updateResult.isSuccess(), isTrue);

      final getResult = await repository.getById(c.id);
      getResult.fold(
        (found) {
          expect(found.name, 'Updated Name');
          expect(found.isActive, isFalse);
        },
        (_) => fail('Should not fail'),
      );
    });

    test('delete should remove credential', () async {
      final c = credential();
      await repository.save(c);

      final deleteResult = await repository.delete(c.id);
      expect(deleteResult.isSuccess(), isTrue);

      final getResult = await repository.getById(c.id);
      expect(getResult.isError(), isTrue);
    });

    test('getActive should return only active credentials', () async {
      final active = credential(id: 'a', serverId: 's1', name: 'Active');
      final inactive = credential(
        id: 'b',
        serverId: 's2',
        name: 'Inactive',
      ).copyWith(isActive: false);
      await repository.save(active);
      await repository.save(inactive);

      final result = await repository.getActive();
      expect(result.isSuccess(), isTrue);
      result.fold(
        (list) {
          expect(list.length, 1);
          expect(list.first.id, 'a');
        },
        (_) => fail('Should not fail'),
      );
    });

    test('updateLastUsed should not fail for existing credential', () async {
      final c = credential();
      await repository.save(c);

      final result = await repository.updateLastUsed(c.id);
      expect(result.isSuccess(), isTrue);
    });

    test('watchAll should emit list when credentials change', () async {
      final c = credential();
      final emissions = <List<ServerCredential>>[];
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
