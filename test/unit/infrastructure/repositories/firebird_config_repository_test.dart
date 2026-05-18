import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/firebird_config_repository.dart';
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
    when(
      () => mockSecure.storePassword(
        key: any(named: 'key'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => const rd.Success(unit));
    when(
      () => mockSecure.getPassword(key: any(named: 'key')),
    ).thenAnswer((_) async => const rd.Success('vault-password'));
    when(
      () => mockSecure.deletePassword(key: any(named: 'key')),
    ).thenAnswer((_) async => const rd.Success(unit));
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

        final loaded = await repository.getById('fb-a');
        expect(loaded.isSuccess(), isTrue);
        final entity = loaded.getOrNull()!;
        expect(entity.password, 'vault-password');
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
  });
}
