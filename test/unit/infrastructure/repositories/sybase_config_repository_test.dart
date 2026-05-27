import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/sybase_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSecureCredentialService extends Mock
    implements ISecureCredentialService {}

void main() {
  late AppDatabase database;
  late _MockSecureCredentialService mockSecure;
  late SybaseConfigRepository repository;

  SybaseConfig buildConfig({
    required String id,
    String name = 'sy-name',
    String serverName = 'srv',
    String databaseName = 'db',
    String databaseFile = '',
    int port = 2638,
    String username = 'dba',
    String password = 'secret',
    bool enabled = true,
    bool isReplicationEnvironment = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = createdAt ?? DateTime.utc(2026, 5, 27);
    return SybaseConfig(
      id: id,
      name: name,
      serverName: serverName,
      databaseName: DatabaseName(databaseName),
      databaseFile: databaseFile,
      port: PortNumber(port),
      username: username,
      password: password,
      enabled: enabled,
      isReplicationEnvironment: isReplicationEnvironment,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  setUp(() {
    database = AppDatabase.inMemory();
    mockSecure = _MockSecureCredentialService();
    repository = SybaseConfigRepository(database, mockSecure);

    // Espelha o backing store real do secure storage para distinguir
    // chave por configId.
    final vault = <String, String>{};
    when(
      () => mockSecure.storePassword(
        key: any(named: 'key'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key]! as String;
      final value = invocation.namedArguments[#password]! as String;
      vault[key] = value;
      return const rd.Success(unit);
    });
    when(
      () => mockSecure.getPassword(key: any(named: 'key')),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key]! as String;
      final stored = vault[key];
      if (stored == null) {
        return rd.Failure(NotFoundFailure(message: 'no password for $key'));
      }
      return rd.Success(stored);
    });
    when(
      () => mockSecure.deletePassword(key: any(named: 'key')),
    ).thenAnswer((invocation) async {
      vault.remove(invocation.namedArguments[#key]! as String);
      return const rd.Success(unit);
    });
  });

  tearDown(() async {
    await database.close();
  });

  group('SybaseConfigRepository', () {
    test('create stores password in secure storage and persists row', () async {
      final cfg = buildConfig(id: 'sy-a', password: 'topsecret');

      final created = await repository.create(cfg);
      expect(created.isSuccess(), isTrue);

      verify(
        () => mockSecure.storePassword(
          key: SecureCredentialKeys.sybasePasswordKey('sy-a'),
          password: 'topsecret',
        ),
      ).called(1);

      final row = await database.sybaseConfigDao.getById('sy-a');
      expect(row, isNotNull);
      // Coluna SQLite NUNCA grava texto puro da senha.
      expect(row!.password, isEmpty);
    });

    test('getById maps Sybase fields including replication flag', () async {
      final cfg = buildConfig(
        id: 'sy-b',
        databaseName: 'mydb',
        port: 2639,
        isReplicationEnvironment: true,
      );
      await repository.create(cfg);

      final loaded = await repository.getById('sy-b');
      expect(loaded.isSuccess(), isTrue);

      final entity = loaded.getOrNull()!;
      expect(entity.password, 'secret');
      expect(entity.databaseNameValue, 'mydb');
      expect(entity.portValue, 2639);
      expect(entity.isReplicationEnvironment, isTrue);
    });

    test('getEnabled returns only enabled rows', () async {
      await repository.create(buildConfig(id: 'on'));
      await repository.create(buildConfig(id: 'off', enabled: false));

      final result = await repository.getEnabled();
      expect(result.isSuccess(), isTrue);
      final list = result.getOrNull()!;
      expect(list.length, 1);
      expect(list.single.id, 'on');
    });

    test('update persists changes (password + replication flag)', () async {
      await repository.create(buildConfig(id: 'u1'));

      final revised = buildConfig(
        id: 'u1',
        password: 'newpw',
        isReplicationEnvironment: true,
      );
      final updated = await repository.update(revised);
      expect(updated.isSuccess(), isTrue);

      verify(
        () => mockSecure.storePassword(
          key: SecureCredentialKeys.sybasePasswordKey('u1'),
          password: 'newpw',
        ),
      ).called(1);

      final loaded = await repository.getById('u1');
      expect(loaded.getOrNull()!.password, 'newpw');
      expect(loaded.getOrNull()!.isReplicationEnvironment, isTrue);
    });

    test('delete removes row and clears secure password', () async {
      await repository.create(buildConfig(id: 'del1'));

      final deleted = await repository.delete('del1');
      expect(deleted.isSuccess(), isTrue);

      final missing = await repository.getById('del1');
      expect(missing.isError(), isTrue);
      expect(missing.exceptionOrNull(), isA<NotFoundFailure>());

      verify(
        () => mockSecure.deletePassword(
          key: SecureCredentialKeys.sybasePasswordKey('del1'),
        ),
      ).called(1);
    });

    test('getById returns NotFoundFailure when id is missing', () async {
      final result = await repository.getById('nope');
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<NotFoundFailure>());
    });

    test('rowToEntity falls back to serverName when database_name is empty',
        () async {
      // Simula linha legada (pré-migração v3) com `database_name` vazio.
      final now = DateTime.utc(2026, 5, 27);
      await database.sybaseConfigDao.insertConfig(
        SybaseConfigsTableCompanion.insert(
          id: 'legacy-1',
          name: 'legacy',
          serverName: 'engname',
          databaseName: '',
          databaseFile: '',
          username: 'dba',
          password: '',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final read = await repository.getById('legacy-1');
      expect(read.isSuccess(), isTrue);
      // Fallback: databaseName vazio resolve para serverName.
      expect(read.getOrNull()!.databaseNameValue, 'engname');
    });
  });
}
