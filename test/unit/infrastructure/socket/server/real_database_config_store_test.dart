import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/socket/server/real_database_config_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSybaseRepo extends Mock implements ISybaseConfigRepository {}
class _MockSqlServerRepo extends Mock implements ISqlServerConfigRepository {}
class _MockPostgresRepo extends Mock implements IPostgresConfigRepository {}

void main() {
  late _MockSybaseRepo sybaseRepo;
  late _MockSqlServerRepo sqlRepo;
  late _MockPostgresRepo pgRepo;
  late RealDatabaseConfigStore store;

  final sybaseCfg = SybaseConfig(
    id: 'sb-1',
    name: 'n',
    serverName: 's',
    databaseName: DatabaseName('d'),
    username: 'u',
    password: 'p',
  );
  final sqlCfg = SqlServerConfig(
    id: 'sql-1',
    name: 'n',
    server: 's',
    database: DatabaseName('d'),
    username: 'u',
    password: 'p',
  );
  final pgCfg = PostgresConfig(
    id: 'pg-1',
    name: 'n',
    host: 'h',
    database: DatabaseName('d'),
    username: 'u',
    password: 'p',
  );

  setUpAll(() {
    registerFallbackValue(sybaseCfg);
    registerFallbackValue(sqlCfg);
    registerFallbackValue(pgCfg);
  });

  setUp(() {
    sybaseRepo = _MockSybaseRepo();
    sqlRepo = _MockSqlServerRepo();
    pgRepo = _MockPostgresRepo();
    store = RealDatabaseConfigStore(
      sybaseRepository: sybaseRepo,
      sqlServerRepository: sqlRepo,
      postgresRepository: pgRepo,
    );
  });

  group('list', () {
    test('Sybase: serializa entities sem incluir password', () async {
      when(() => sybaseRepo.getAll())
          .thenAnswer((_) async => rd.Success([sybaseCfg]));
      final outcome = await store.list(RemoteDatabaseType.sybase);
      expect(outcome.success, isTrue);
      expect(outcome.configs, hasLength(1));
      expect(outcome.configs!.first['username'], 'u');
      expect(outcome.configs!.first.containsKey('password'), isFalse);
    });

    test('SqlServer: dispatches para repo correto', () async {
      when(() => sqlRepo.getAll())
          .thenAnswer((_) async => rd.Success([sqlCfg]));
      final outcome = await store.list(RemoteDatabaseType.sqlServer);
      expect(outcome.success, isTrue);
      expect(outcome.configs, hasLength(1));
      verify(() => sqlRepo.getAll()).called(1);
      verifyNever(() => sybaseRepo.getAll());
    });

    test('Postgres: dispatches para repo correto', () async {
      when(() => pgRepo.getAll())
          .thenAnswer((_) async => rd.Success([pgCfg]));
      final outcome = await store.list(RemoteDatabaseType.postgres);
      expect(outcome.success, isTrue);
      verify(() => pgRepo.getAll()).called(1);
    });

    test('falha do repo vira outcome.failure', () async {
      when(() => sybaseRepo.getAll())
          .thenAnswer((_) async => rd.Failure(Exception('db error')));
      final outcome = await store.list(RemoteDatabaseType.sybase);
      expect(outcome.success, isFalse);
      expect(outcome.errorCode, ErrorCode.unknown);
    });

    test('mensagem "not found" mapeia para fileNotFound', () async {
      when(() => sybaseRepo.getAll()).thenAnswer(
        (_) async => rd.Failure(Exception('Tabela nao encontrada')),
      );
      final outcome = await store.list(RemoteDatabaseType.sybase);
      expect(outcome.errorCode, ErrorCode.fileNotFound);
    });
  });

  group('create', () {
    test('Sybase: deserializa map -> entity, persiste, retorna config', () async {
      when(() => sybaseRepo.create(any()))
          .thenAnswer((_) async => rd.Success(sybaseCfg));
      final outcome = await store.create(
        RemoteDatabaseType.sybase,
        const {
          'name': 'n',
          'serverName': 's',
          'databaseName': 'd',
          'username': 'u',
          'password': 'p',
        },
      );
      expect(outcome.success, isTrue);
      expect(outcome.config, isNotNull);
      expect(outcome.config!['username'], 'u');
      verify(() => sybaseRepo.create(any())).called(1);
    });

    test('payload sem campos obrigatorios -> invalidRequest', () async {
      final outcome = await store.create(
        RemoteDatabaseType.sybase,
        const {'name': 'n'}, // faltam campos
      );
      expect(outcome.success, isFalse);
      expect(outcome.errorCode, ErrorCode.invalidRequest);
      verifyNever(() => sybaseRepo.create(any()));
    });
  });

  group('update', () {
    test('Sybase: dispatches update', () async {
      when(() => sybaseRepo.update(any()))
          .thenAnswer((_) async => rd.Success(sybaseCfg));
      final outcome = await store.update(
        RemoteDatabaseType.sybase,
        const {
          'id': 'sb-1',
          'name': 'updated',
          'serverName': 's',
          'databaseName': 'd',
          'username': 'u',
          'password': 'p',
        },
      );
      expect(outcome.success, isTrue);
    });
  });

  group('delete', () {
    test('Sybase: dispatches delete pelo id', () async {
      when(() => sybaseRepo.delete('sb-1'))
          .thenAnswer((_) async => const rd.Success('ok'));
      final outcome = await store.delete(RemoteDatabaseType.sybase, 'sb-1');
      expect(outcome.success, isTrue);
      verify(() => sybaseRepo.delete('sb-1')).called(1);
    });

    test('falha do repo vira outcome.failure', () async {
      when(() => sybaseRepo.delete('sb-1'))
          .thenAnswer((_) async => rd.Failure(Exception('FK constraint')));
      final outcome = await store.delete(RemoteDatabaseType.sybase, 'sb-1');
      expect(outcome.success, isFalse);
      expect(outcome.errorCode, ErrorCode.unknown);
    });
  });
}
