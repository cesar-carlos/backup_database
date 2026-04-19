import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/socket/server/database_connection_prober.dart';
import 'package:backup_database/infrastructure/socket/server/real_database_connection_prober.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSybaseService extends Mock implements ISybaseBackupService {}
class _MockSqlServerService extends Mock implements ISqlServerBackupService {}
class _MockPostgresService extends Mock implements IPostgresBackupService {}
class _MockSybaseRepo extends Mock implements ISybaseConfigRepository {}
class _MockSqlServerRepo extends Mock implements ISqlServerConfigRepository {}
class _MockPostgresRepo extends Mock implements IPostgresConfigRepository {}

void main() {
  late _MockSybaseService sybaseSvc;
  late _MockSqlServerService sqlSvc;
  late _MockPostgresService pgSvc;
  late _MockSybaseRepo sybaseRepo;
  late _MockSqlServerRepo sqlRepo;
  late _MockPostgresRepo pgRepo;
  late RealDatabaseConnectionProber prober;

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
    sybaseSvc = _MockSybaseService();
    sqlSvc = _MockSqlServerService();
    pgSvc = _MockPostgresService();
    sybaseRepo = _MockSybaseRepo();
    sqlRepo = _MockSqlServerRepo();
    pgRepo = _MockPostgresRepo();
    prober = RealDatabaseConnectionProber(
      sybaseService: sybaseSvc,
      sqlServerService: sqlSvc,
      postgresService: pgSvc,
      sybaseRepository: sybaseRepo,
      sqlServerRepository: sqlRepo,
      postgresRepository: pgRepo,
    );
  });

  group('RealDatabaseConnectionProber — Sybase', () {
    test('por id: sucesso (testConnection true)', () async {
      when(() => sybaseRepo.getById('sb-1'))
          .thenAnswer((_) async => rd.Success(sybaseCfg));
      when(() => sybaseSvc.testConnection(any()))
          .thenAnswer((_) async => const rd.Success(true));

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigById('sb-1'),
      );
      expect(outcome.connected, isTrue);
      expect(outcome.latencyMs, greaterThanOrEqualTo(0));
      verify(() => sybaseSvc.testConnection(sybaseCfg)).called(1);
    });

    test('por id: testConnection false vira authenticationFailed', () async {
      when(() => sybaseRepo.getById('sb-1'))
          .thenAnswer((_) async => rd.Success(sybaseCfg));
      when(() => sybaseSvc.testConnection(any()))
          .thenAnswer((_) async => const rd.Success(false));

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigById('sb-1'),
      );
      expect(outcome.connected, isFalse);
      expect(outcome.errorCode, ErrorCode.authenticationFailed);
    });

    test('por id: config nao encontrada -> fileNotFound', () async {
      when(() => sybaseRepo.getById('xx'))
          .thenAnswer((_) async => rd.Failure(Exception('not found')));

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigById('xx'),
      );
      expect(outcome.connected, isFalse);
      expect(outcome.errorCode, ErrorCode.fileNotFound);
    });

    test('por id: testConnection com Failure timeout vira ErrorCode.timeout',
        () async {
      when(() => sybaseRepo.getById('sb-1'))
          .thenAnswer((_) async => rd.Success(sybaseCfg));
      when(() => sybaseSvc.testConnection(any()))
          .thenAnswer((_) async => rd.Failure(Exception('Timeout expirou')));

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigById('sb-1'),
      );
      expect(outcome.errorCode, ErrorCode.timeout);
    });

    test('por id: testConnection com Failure socket -> ioError', () async {
      when(() => sybaseRepo.getById('sb-1'))
          .thenAnswer((_) async => rd.Success(sybaseCfg));
      when(() => sybaseSvc.testConnection(any()))
          .thenAnswer((_) async => rd.Failure(Exception('Socket connection refused')));

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigById('sb-1'),
      );
      expect(outcome.errorCode, ErrorCode.ioError);
    });

    test('por id: testConnection com Failure auth-related -> authFailed',
        () async {
      when(() => sybaseRepo.getById('sb-1'))
          .thenAnswer((_) async => rd.Success(sybaseCfg));
      when(() => sybaseSvc.testConnection(any())).thenAnswer(
        (_) async => rd.Failure(Exception('Login falhou: senha invalida')),
      );

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigById('sb-1'),
      );
      expect(outcome.errorCode, ErrorCode.authenticationFailed);
    });

    test('ad-hoc: passa map -> entity sem persistir', () async {
      when(() => sybaseSvc.testConnection(any()))
          .thenAnswer((_) async => const rd.Success(true));

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigAdhoc(<String, dynamic>{
          'name': 'test',
          'serverName': 'localhost',
          'databaseName': 'app',
          'username': 'u',
        }),
      );
      expect(outcome.connected, isTrue);
      verifyNever(() => sybaseRepo.getById(any()));
    });

    test('ad-hoc: payload invalido -> invalidRequest', () async {
      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigAdhoc(<String, dynamic>{
          // sem campos obrigatorios
        }),
      );
      expect(outcome.connected, isFalse);
      expect(outcome.errorCode, ErrorCode.invalidRequest);
      verifyNever(() => sybaseSvc.testConnection(any()));
    });
  });

  group('RealDatabaseConnectionProber — SqlServer', () {
    test('despacha por tipo correto', () async {
      when(() => sqlRepo.getById('sql-1'))
          .thenAnswer((_) async => rd.Success(sqlCfg));
      when(() => sqlSvc.testConnection(any()))
          .thenAnswer((_) async => const rd.Success(true));

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sqlServer,
        configRef: const DatabaseConfigById('sql-1'),
      );
      expect(outcome.connected, isTrue);
      verify(() => sqlSvc.testConnection(sqlCfg)).called(1);
      verifyNever(() => sybaseSvc.testConnection(any()));
      verifyNever(() => pgSvc.testConnection(any()));
    });
  });

  group('RealDatabaseConnectionProber — Postgres', () {
    test('despacha por tipo correto', () async {
      when(() => pgRepo.getById('pg-1'))
          .thenAnswer((_) async => rd.Success(pgCfg));
      when(() => pgSvc.testConnection(any()))
          .thenAnswer((_) async => const rd.Success(true));

      final outcome = await prober.probe(
        databaseType: RemoteDatabaseType.postgres,
        configRef: const DatabaseConfigById('pg-1'),
      );
      expect(outcome.connected, isTrue);
      verify(() => pgSvc.testConnection(pgCfg)).called(1);
    });
  });

  group('Latencia', () {
    test('latencyMs e nao-negativo em todos os paths', () async {
      // sucesso
      when(() => sybaseRepo.getById(any()))
          .thenAnswer((_) async => rd.Success(sybaseCfg));
      when(() => sybaseSvc.testConnection(any()))
          .thenAnswer((_) async => const rd.Success(true));
      var outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigById('x'),
      );
      expect(outcome.latencyMs, greaterThanOrEqualTo(0));

      // falha
      when(() => sybaseRepo.getById(any()))
          .thenAnswer((_) async => rd.Failure(Exception('not found')));
      outcome = await prober.probe(
        databaseType: RemoteDatabaseType.sybase,
        configRef: const DatabaseConfigById('x'),
      );
      expect(outcome.latencyMs, greaterThanOrEqualTo(0));
    });
  });
}
