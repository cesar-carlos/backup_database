import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/base_database_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockSecureCredentialService extends Mock
    implements ISecureCredentialService {}

class _MemRow {
  _MemRow({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String database;
  final String username;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class _TestConfig extends DatabaseConnectionConfig {
  _TestConfig({
    required super.id,
    required super.name,
    required this.hostValue,
    required super.port,
    required super.username,
    required super.password,
    required super.enabled,
    required super.createdAt,
    required super.updatedAt,
    required this.databaseValue,
  });

  final String hostValue;
  final String databaseValue;

  @override
  DatabaseType get databaseType => DatabaseType.postgresql;

  @override
  String get host => hostValue;

  @override
  DatabaseName get primaryDatabase => DatabaseName(databaseValue);
}

class _FakeConfigRepository
    extends BaseDatabaseConfigRepository<_TestConfig, _MemRow> {
  _FakeConfigRepository(
    super.database,
    super.secureCredentialService,
  );

  final List<_MemRow> _rows = <_MemRow>[];

  @override
  String credentialKeyFor(String configId) => 'test_cred:$configId';

  @override
  Future<List<_MemRow>> fetchAllRows() async => List<_MemRow>.from(_rows);

  @override
  Future<List<_MemRow>> fetchEnabledRows() async =>
      _rows.where((r) => r.enabled).toList();

  @override
  Future<_MemRow?> fetchRowById(String id) async {
    for (final r in _rows) {
      if (r.id == id) {
        return r;
      }
    }
    return null;
  }

  @override
  Future<void> writeInsert(_TestConfig config) async {
    _rows.add(
      _MemRow(
        id: config.id,
        name: config.name,
        host: config.hostValue,
        port: config.portValue,
        database: config.databaseValue,
        username: config.username,
        enabled: config.enabled,
        createdAt: config.createdAt,
        updatedAt: config.updatedAt,
      ),
    );
  }

  @override
  Future<void> writeUpdate(_TestConfig config) async {
    final i = _rows.indexWhere((r) => r.id == config.id);
    if (i < 0) {
      return;
    }
    _rows[i] = _MemRow(
      id: config.id,
      name: config.name,
      host: config.hostValue,
      port: config.portValue,
      database: config.databaseValue,
      username: config.username,
      enabled: config.enabled,
      createdAt: config.createdAt,
      updatedAt: config.updatedAt,
    );
  }

  @override
  Future<void> writeDelete(String id) async {
    _rows.removeWhere((r) => r.id == id);
  }

  @override
  Future<_TestConfig> rowToEntity(_MemRow row) async {
    final password = await credentials.readPasswordOrEmpty(
      credentialKeyFor(row.id),
    );
    return _TestConfig(
      id: row.id,
      name: row.name,
      hostValue: row.host,
      port: PortNumber(row.port),
      databaseValue: row.database,
      username: row.username,
      password: password,
      enabled: row.enabled,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}

class _FakeWithOnBeforeHook extends _FakeConfigRepository {
  _FakeWithOnBeforeHook(
    super.database,
    super.secureCredentialService,
  );

  int onBeforeDeleteCallCount = 0;
  String? lastOnBeforeDeleteId;

  @override
  Future<void> onBeforeDelete(String id) async {
    onBeforeDeleteCallCount++;
    lastOnBeforeDeleteId = id;
  }
}

void main() {
  late _MockAppDatabase mockDatabase;
  late _MockSecureCredentialService mockSecure;
  late _FakeConfigRepository repo;

  setUp(() {
    mockDatabase = _MockAppDatabase();
    mockSecure = _MockSecureCredentialService();
    repo = _FakeConfigRepository(mockDatabase, mockSecure);
    when(
      () => mockSecure.storePassword(
        key: any(named: 'key'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => const rd.Success(unit));
    when(
      () => mockSecure.getPassword(key: any(named: 'key')),
    ).thenAnswer((_) async => const rd.Success('stored-secret'));
    when(
      () => mockSecure.deletePassword(key: any(named: 'key')),
    ).thenAnswer((_) async => const rd.Success(unit));
  });

  group('BaseDatabaseConfigRepository', () {
    test('create then getById restores password from secure store', () async {
      final now = DateTime.now();
      final input = _TestConfig(
        id: 'c1',
        name: 'cfg',
        hostValue: 'h',
        port: PortNumber(5432),
        databaseValue: 'db1',
        username: 'u',
        password: 'plain',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );

      final created = await repo.create(input);
      expect(created.isSuccess(), isTrue);

      final loaded = await repo.getById('c1');
      expect(loaded.isSuccess(), isTrue);
      expect(loaded.getOrNull()!.password, 'stored-secret');

      verify(
        () => mockSecure.storePassword(
          key: 'test_cred:c1',
          password: 'plain',
        ),
      ).called(1);
      verify(() => mockSecure.getPassword(key: 'test_cred:c1')).called(1);
    });

    test('delete removes row and credential', () async {
      final now = DateTime.now();
      final input = _TestConfig(
        id: 'd1',
        name: 'n',
        hostValue: 'h',
        port: PortNumber(5432),
        databaseValue: 'db',
        username: 'u',
        password: 'p',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );
      await repo.create(input);

      final deleted = await repo.delete('d1');
      expect(deleted.isSuccess(), isTrue);

      final missing = await repo.getById('d1');
      expect(missing.isError(), isTrue);

      verify(() => mockSecure.deletePassword(key: 'test_cred:d1')).called(1);
    });

    test('getById returns NotFoundFailure when id is missing', () async {
      final result = await repo.getById('missing');
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<NotFoundFailure>());
    });

    test('getAll returns every stored config', () async {
      final now = DateTime.now();
      final a = _TestConfig(
        id: 'ga',
        name: 'a',
        hostValue: 'h1',
        port: PortNumber(5432),
        databaseValue: 'db',
        username: 'u',
        password: 'p1',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );
      final b = _TestConfig(
        id: 'gb',
        name: 'b',
        hostValue: 'h2',
        port: PortNumber(5433),
        databaseValue: 'db2',
        username: 'u2',
        password: 'p2',
        enabled: false,
        createdAt: now,
        updatedAt: now,
      );
      await repo.create(a);
      await repo.create(b);

      final all = await repo.getAll();
      expect(all.isSuccess(), isTrue);
      final list = all.getOrNull()!;
      expect(list.length, 2);
      expect(list.map((e) => e.id).toSet(), equals(<String>{'ga', 'gb'}));
    });

    test('getEnabled returns only enabled rows', () async {
      final now = DateTime.now();
      await repo.create(
        _TestConfig(
          id: 'e_on',
          name: 'on',
          hostValue: 'h',
          port: PortNumber(5432),
          databaseValue: 'db',
          username: 'u',
          password: 'p',
          enabled: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repo.create(
        _TestConfig(
          id: 'e_off',
          name: 'off',
          hostValue: 'h',
          port: PortNumber(5432),
          databaseValue: 'db',
          username: 'u',
          password: 'p',
          enabled: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final enabled = await repo.getEnabled();
      expect(enabled.isSuccess(), isTrue);
      final enabledConfigs = enabled.getOrNull()!;
      expect(enabledConfigs.length, 1);
      expect(enabledConfigs.single.id, 'e_on');
    });

    test('update persists field changes and re-stores password', () async {
      final now = DateTime.now();
      final original = _TestConfig(
        id: 'u1',
        name: 'old',
        hostValue: 'h0',
        port: PortNumber(5432),
        databaseValue: 'db',
        username: 'u',
        password: 'oldpw',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );
      await repo.create(original);

      final revised = _TestConfig(
        id: 'u1',
        name: 'new',
        hostValue: 'h9',
        port: PortNumber(5432),
        databaseValue: 'db',
        username: 'u',
        password: 'newpw',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );
      final updated = await repo.update(revised);
      expect(updated.isSuccess(), isTrue);

      final loaded = await repo.getById('u1');
      expect(loaded.isSuccess(), isTrue);
      expect(loaded.getOrNull()!.name, 'new');
      expect(loaded.getOrNull()!.hostValue, 'h9');

      verify(
        () => mockSecure.storePassword(
          key: 'test_cred:u1',
          password: 'newpw',
        ),
      ).called(1);
    });

    test('delete invokes onBeforeDelete before credential removal', () async {
      final hookRepo = _FakeWithOnBeforeHook(mockDatabase, mockSecure);
      final now = DateTime.now();
      final input = _TestConfig(
        id: 'hook1',
        name: 'h',
        hostValue: 'host',
        port: PortNumber(5432),
        databaseValue: 'db',
        username: 'u',
        password: 'pw',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );
      await hookRepo.create(input);

      final deleted = await hookRepo.delete('hook1');

      expect(deleted.isSuccess(), isTrue);
      expect(hookRepo.onBeforeDeleteCallCount, 1);
      expect(hookRepo.lastOnBeforeDeleteId, 'hook1');
      verify(() => mockSecure.deletePassword(key: 'test_cred:hook1')).called(1);
    });

    test('create returns failure when storePassword fails', () async {
      when(
        () => mockSecure.storePassword(
          key: any(named: 'key'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => rd.Failure(Exception('vault full')));

      final now = DateTime.now();
      final input = _TestConfig(
        id: 'bad-store',
        name: 'n',
        hostValue: 'h',
        port: PortNumber(5432),
        databaseValue: 'db',
        username: 'u',
        password: 'p',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );

      final created = await repo.create(input);

      expect(created.isError(), isTrue);
      final missing = await repo.getById('bad-store');
      expect(missing.isError(), isTrue);
    });
  });
}
