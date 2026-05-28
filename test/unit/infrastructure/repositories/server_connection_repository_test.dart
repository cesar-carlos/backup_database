import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/server_connection_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart' as rd;

void main() {
  late AppDatabase database;
  late _InMemorySecureCredentialService vault;
  late ServerConnectionRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    vault = _InMemorySecureCredentialService();
    repository = ServerConnectionRepository(database, vault);
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
      String password = 'pwd',
    }) {
      return ServerConnection(
        id: id,
        name: name,
        serverId: 'server-1',
        host: host,
        port: port,
        password: password,
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
          expect(list.first.password, c.password);
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
          expect(found.password, c.password);
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

    test(
      'update should persist changes and rotate password in vault',
      () async {
        final c = connection();
        await repository.save(c);
        final updated = c.copyWith(
          name: 'Updated Name',
          port: 9530,
          password: 'rotated',
        );

        final updateResult = await repository.update(updated);
        expect(updateResult.isSuccess(), isTrue);

        final getResult = await repository.getById(c.id);
        getResult.fold(
          (found) {
            expect(found.name, 'Updated Name');
            expect(found.port, 9530);
            expect(found.password, 'rotated');
          },
          (_) => fail('Should not fail'),
        );
      },
    );

    test('delete should remove connection AND clear vault entry', () async {
      final c = connection();
      await repository.save(c);

      final deleteResult = await repository.delete(c.id);
      expect(deleteResult.isSuccess(), isTrue);

      final getResult = await repository.getById(c.id);
      expect(getResult.isError(), isTrue);
      expect(vault.contains('server_connection_${c.id}'), isFalse);
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
      expect(emissions.last.first.password, c.password);

      await sub.cancel();
    });

    test(
      '§audit-2026-05-28 P0: password is NEVER persisted plaintext to SQLite',
      () async {
        // Regressão: antes esse teste falhava — a senha era persistida em
        // texto na coluna `server_connections.password`, deixando o backup
        // do SQLite, exports e diagnóstico vulneráveis. Agora a senha vai
        // só para o vault DPAPI e a coluna fica vazia.
        final c = connection(password: 'super-secret-2026');
        await repository.save(c);

        final rawRow = await database.serverConnectionDao.getById(c.id);
        expect(rawRow, isNotNull);
        expect(
          rawRow!.password,
          '',
          reason:
              'A coluna password deve ficar vazia; o segredo fica no vault.',
        );
        expect(vault.read('server_connection_${c.id}'), 'super-secret-2026');
      },
    );

    test(
      '§audit-2026-05-28 P0: legacy plaintext rows are auto-migrated on read',
      () async {
        // Cliente atualizando de uma versão pre-P0 vai ter linhas com
        // password plaintext. Na primeira leitura, o repo migra
        // transparentemente: move para o vault e zera a coluna do DB.
        const legacyId = 'legacy-1';
        await database.serverConnectionDao.insertConnection(
          ServerConnectionsTableData(
            id: legacyId,
            name: 'Legacy',
            serverId: 'srv',
            host: '10.0.0.1',
            port: 9527,
            password: 'legacy-plaintext',
            isOnline: false,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ).toCompanion(true),
        );

        final result = await repository.getById(legacyId);
        expect(result.isSuccess(), isTrue);
        result.fold(
          (found) => expect(found.password, 'legacy-plaintext'),
          (_) => fail('Should not fail'),
        );

        // Coluna agora deve estar limpa, vault deve ter o segredo.
        final rawAfter = await database.serverConnectionDao.getById(legacyId);
        expect(rawAfter!.password, '');
        expect(vault.read('server_connection_$legacyId'), 'legacy-plaintext');
      },
    );

    test(
      '§audit-2026-05-28 P0: per-connection vault key isolates secrets',
      () async {
        final a = connection(id: 'conn-a', password: 'pwd-a');
        final b = connection(id: 'conn-b', password: 'pwd-b');
        await repository.save(a);
        await repository.save(b);

        expect(vault.read('server_connection_conn-a'), 'pwd-a');
        expect(vault.read('server_connection_conn-b'), 'pwd-b');

        // Deleta um: o segredo do outro continua intacto.
        await repository.delete('conn-a');
        expect(vault.contains('server_connection_conn-a'), isFalse);
        expect(vault.read('server_connection_conn-b'), 'pwd-b');
      },
    );
  });
}

/// In-memory `ISecureCredentialService` that mimics
/// `MachineScopeSecureCredentialService` for tests without DPAPI / file
/// system access. Only the surface used by `ServerConnectionRepository`
/// is implemented; other methods throw `UnimplementedError` on purpose
/// so future callers don't silently take a no-op path.
class _InMemorySecureCredentialService implements ISecureCredentialService {
  final Map<String, String> _passwords = {};

  bool contains(String key) => _passwords.containsKey(key);
  String? read(String key) => _passwords[key];

  @override
  Future<rd.Result<Unit>> storePassword({
    required String key,
    required String password,
  }) async {
    _passwords[key] = password;
    return const rd.Success(unit);
  }

  @override
  Future<rd.Result<String>> getPassword({required String key}) async {
    final value = _passwords[key];
    if (value == null) {
      return const rd.Success('');
    }
    return rd.Success(value);
  }

  @override
  Future<rd.Result<Unit>> deletePassword({required String key}) async {
    _passwords.remove(key);
    return const rd.Success(unit);
  }

  @override
  Future<rd.Result<Unit>> storeToken({
    required String key,
    required Map<String, dynamic> tokenData,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<rd.Result<Map<String, dynamic>>> getToken({required String key}) {
    throw UnimplementedError();
  }

  @override
  Future<rd.Result<Unit>> deleteToken({required String key}) {
    throw UnimplementedError();
  }

  @override
  Future<rd.Result<bool>> containsKey({required String key}) async {
    return rd.Success(_passwords.containsKey(key));
  }

  @override
  Future<rd.Result<Unit>> deleteAll() async {
    _passwords.clear();
    return const rd.Success(unit);
  }

  @override
  Future<rd.Result<Map<String, String>>> readAll() async {
    return rd.Success(Map<String, String>.from(_passwords));
  }
}
