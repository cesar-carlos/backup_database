import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/firebird_config_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSecureCredentialService extends Mock
    implements ISecureCredentialService {}

void main() {
  late AppDatabase database;
  late _MockSecureCredentialService mockSecure;
  late FirebirdConfigRepository repository;

  FirebirdConfig buildConfig({
    required String id,
    String name = 'fb-name',
    String host = 'localhost',
    String databaseFile = r'C:\data\app.fdb',
    String username = 'SYSDBA',
    String password = 'masterkey',
    PortNumber? port,
    String? aliasName,
    bool useEmbedded = false,
    String? clientLibraryPath,
    FirebirdServerVersionHint serverVersionHint =
        FirebirdServerVersionHint.auto,
    FirebirdServiceManagerMode serviceManagerMode =
        FirebirdServiceManagerMode.auto,
    String cryptKey = '',
    bool enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = createdAt ?? DateTime.utc(2026, 5, 16);
    return FirebirdConfig(
      id: id,
      name: name,
      host: host,
      databaseFile: databaseFile,
      username: username,
      password: password,
      port: port ?? PortNumber(3050),
      aliasName: aliasName,
      useEmbedded: useEmbedded,
      clientLibraryPath: clientLibraryPath,
      serverVersionHint: serverVersionHint,
      serviceManagerMode: serviceManagerMode,
      cryptKey: cryptKey,
      enabled: enabled,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  setUp(() {
    database = AppDatabase.inMemory();
    mockSecure = _MockSecureCredentialService();
    repository = FirebirdConfigRepository(database, mockSecure);

    // Espelhamos o backing store real: cada `storePassword(key, value)`
    // alimenta um map e `getPassword(key)` devolve esse valor. Permite
    // distinguir a chave de senha do utilizador (`firebird_password_*`)
    // da chave de criptografia (`firebird_crypt_key_*`) que agora
    // tambem vive em secure storage (sem coluna SQLite plaintext).
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
        return rd.Failure(
          NotFoundFailure(message: 'no password for $key'),
        );
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

  group('FirebirdConfigRepository', () {
    test(
      'create stores password key and getById maps Firebird fields',
      () async {
        final cfg = buildConfig(
          id: 'fb-a',
          aliasName: 'alias1',
          serverVersionHint: FirebirdServerVersionHint.v40,
          serviceManagerMode: FirebirdServiceManagerMode.never,
          cryptKey: 'ck-secret',
          clientLibraryPath: r'C:\fb\bin\fbclient.dll',
        );

        final created = await repository.create(cfg);
        expect(created.isSuccess(), isTrue);

        verify(
          () => mockSecure.storePassword(
            key: SecureCredentialKeys.firebirdPasswordKey('fb-a'),
            password: 'masterkey',
          ),
        ).called(1);
        // cryptKey tambem vive em secure storage agora (sem texto puro
        // na coluna SQLite). Verificamos a chamada de armazenamento.
        verify(
          () => mockSecure.storePassword(
            key: SecureCredentialKeys.firebirdCryptKeyKey('fb-a'),
            password: 'ck-secret',
          ),
        ).called(1);

        final loaded = await repository.getById('fb-a');
        expect(loaded.isSuccess(), isTrue);
        final entity = loaded.getOrNull()!;
        // Vault devolve o mesmo valor que foi salvo (ja nao ha o stub
        // generico `vault-password`); ver setUp.
        expect(entity.password, 'masterkey');
        expect(entity.aliasName, 'alias1');
        expect(entity.serverVersionHint, FirebirdServerVersionHint.v40);
        expect(entity.serviceManagerMode, FirebirdServiceManagerMode.never);
        expect(entity.cryptKey, 'ck-secret');
        expect(entity.clientLibraryPath, r'C:\fb\bin\fbclient.dll');
        expect(entity.databaseFile, r'C:\data\app.fdb');
      },
    );

    test('getEnabled returns only enabled rows', () async {
      final t = DateTime.utc(2026, 5, 16);
      await repository.create(
        buildConfig(id: 'on', createdAt: t),
      );
      await repository.create(
        buildConfig(id: 'off', enabled: false, createdAt: t),
      );

      final result = await repository.getEnabled();
      expect(result.isSuccess(), isTrue);
      final list = result.getOrNull()!;
      expect(list.length, 1);
      expect(list.single.id, 'on');
    });

    test('update persists enum and cryptKey changes', () async {
      final t = DateTime.utc(2026, 5, 16);
      await repository.create(
        buildConfig(
          id: 'u1',
          createdAt: t,
        ),
      );

      final revised = buildConfig(
        id: 'u1',
        serverVersionHint: FirebirdServerVersionHint.v25,
        serviceManagerMode: FirebirdServiceManagerMode.always,
        cryptKey: 'new-ck',
        password: 'newpw',
        createdAt: t,
      );
      final updated = await repository.update(revised);
      expect(updated.isSuccess(), isTrue);

      verify(
        () => mockSecure.storePassword(
          key: SecureCredentialKeys.firebirdPasswordKey('u1'),
          password: 'newpw',
        ),
      ).called(1);

      final loaded = await repository.getById('u1');
      expect(
        loaded.getOrNull()!.serverVersionHint,
        FirebirdServerVersionHint.v25,
      );
      expect(
        loaded.getOrNull()!.serviceManagerMode,
        FirebirdServiceManagerMode.always,
      );
      expect(loaded.getOrNull()!.cryptKey, 'new-ck');
    });

    test('delete removes row and secure password', () async {
      final t = DateTime.utc(2026, 5, 16);
      await repository.create(buildConfig(id: 'del1', createdAt: t));

      final deleted = await repository.delete('del1');
      expect(deleted.isSuccess(), isTrue);

      final missing = await repository.getById('del1');
      expect(missing.isError(), isTrue);
      expect(missing.exceptionOrNull(), isA<NotFoundFailure>());

      verify(
        () => mockSecure.deletePassword(
          key: SecureCredentialKeys.firebirdPasswordKey('del1'),
        ),
      ).called(1);
    });

    test('getById returns NotFoundFailure when id is missing', () async {
      final result = await repository.getById('nope');
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<NotFoundFailure>());
    });

    test(
      'rowToEntity migra cryptKey legada (coluna texto puro) para secure '
      'storage transparentemente e limpa a coluna no SQLite',
      () async {
        // Simula entrada legada: linha gravada antes da auditoria 2026-05-27,
        // com cryptKey na coluna SQLite e nenhum valor em secure storage.
        final now = DateTime.utc(2026, 5, 16);
        await database.firebirdConfigDao.insertConfig(
          FirebirdConfigsTableCompanion.insert(
            id: 'legacy-1',
            name: 'legacy',
            host: 'localhost',
            databaseFile: r'C:\data\legacy.fdb',
            username: 'sysdba',
            password: '',
            cryptKey: const Value('plaintext-from-old-version'),
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Primeira leitura: deve migrar.
        final firstRead = await repository.getById('legacy-1');
        expect(firstRead.isSuccess(), isTrue);
        expect(firstRead.getOrNull()!.cryptKey, 'plaintext-from-old-version');

        // A migracao chamou storePassword com a chave de cryptKey.
        verify(
          () => mockSecure.storePassword(
            key: SecureCredentialKeys.firebirdCryptKeyKey('legacy-1'),
            password: 'plaintext-from-old-version',
          ),
        ).called(1);

        // E zerou a coluna SQLite.
        final rowAfter = await database.firebirdConfigDao.getById('legacy-1');
        expect(rowAfter!.cryptKey, isEmpty);

        // Segunda leitura ja vem do vault — sem nova chamada storePassword
        // (idempotente).
        clearInteractions(mockSecure);
        final secondRead = await repository.getById('legacy-1');
        expect(secondRead.isSuccess(), isTrue);
        expect(
          secondRead.getOrNull()!.cryptKey,
          'plaintext-from-old-version',
        );
        verifyNever(
          () => mockSecure.storePassword(
            key: SecureCredentialKeys.firebirdCryptKeyKey('legacy-1'),
            password: any(named: 'password'),
          ),
        );
      },
    );

    test(
      'rowToEntity nao bloqueia leitura se a migracao falhar; mantem valor '
      'legado na coluna ate proxima tentativa',
      () async {
        final now = DateTime.utc(2026, 5, 16);
        await database.firebirdConfigDao.insertConfig(
          FirebirdConfigsTableCompanion.insert(
            id: 'legacy-2',
            name: 'legacy2',
            host: 'localhost',
            databaseFile: r'C:\data\legacy2.fdb',
            username: 'sysdba',
            password: '',
            cryptKey: const Value('still-here'),
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Override do storePassword especificamente para a chave de
        // cryptKey: simulamos falha de I/O (ex.: keychain bloqueada).
        when(
          () => mockSecure.storePassword(
            key: SecureCredentialKeys.firebirdCryptKeyKey('legacy-2'),
            password: any(named: 'password'),
          ),
        ).thenAnswer(
          (_) async => const rd.Failure(
            ValidationFailure(message: 'keychain locked'),
          ),
        );

        final read = await repository.getById('legacy-2');
        // Leitura completa apesar da migracao ter falhado.
        expect(read.isSuccess(), isTrue);
        expect(read.getOrNull()!.cryptKey, 'still-here');

        // Coluna SQLite preservada (defesa: nao perdemos o segredo).
        final rowAfter = await database.firebirdConfigDao.getById('legacy-2');
        expect(rowAfter!.cryptKey, 'still-here');
      },
    );
  });
}
