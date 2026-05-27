import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_firebird_config_repository.dart';
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

class _MockFirebirdRepo extends Mock implements IFirebirdConfigRepository {}

void main() {
  late _MockSybaseRepo sybaseRepo;
  late _MockSqlServerRepo sqlRepo;
  late _MockPostgresRepo pgRepo;
  late _MockFirebirdRepo fbRepo;
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
  final fbCfg = FirebirdConfig(
    id: 'fb-1',
    name: 'n',
    host: 'h',
    databaseFile: r'C:\data\db.fdb',
    username: 'u',
    password: 'p',
  );

  setUpAll(() {
    registerFallbackValue(sybaseCfg);
    registerFallbackValue(sqlCfg);
    registerFallbackValue(pgCfg);
    registerFallbackValue(fbCfg);
  });

  setUp(() {
    sybaseRepo = _MockSybaseRepo();
    sqlRepo = _MockSqlServerRepo();
    pgRepo = _MockPostgresRepo();
    fbRepo = _MockFirebirdRepo();
    store = RealDatabaseConfigStore(
      sybaseRepository: sybaseRepo,
      sqlServerRepository: sqlRepo,
      postgresRepository: pgRepo,
      firebirdRepository: fbRepo,
    );
  });

  group('list', () {
    test('Sybase: serializa entities sem incluir password', () async {
      when(
        () => sybaseRepo.getAll(),
      ).thenAnswer((_) async => rd.Success([sybaseCfg]));
      final outcome = await store.list(RemoteDatabaseType.sybase);
      expect(outcome.success, isTrue);
      expect(outcome.configs, hasLength(1));
      expect(outcome.configs!.first['username'], 'u');
      expect(outcome.configs!.first.containsKey('password'), isFalse);
    });

    test('SqlServer: dispatches para repo correto', () async {
      when(
        () => sqlRepo.getAll(),
      ).thenAnswer((_) async => rd.Success([sqlCfg]));
      final outcome = await store.list(RemoteDatabaseType.sqlServer);
      expect(outcome.success, isTrue);
      expect(outcome.configs, hasLength(1));
      verify(() => sqlRepo.getAll()).called(1);
      verifyNever(() => sybaseRepo.getAll());
    });

    test('Postgres: dispatches para repo correto', () async {
      when(() => pgRepo.getAll()).thenAnswer((_) async => rd.Success([pgCfg]));
      final outcome = await store.list(RemoteDatabaseType.postgres);
      expect(outcome.success, isTrue);
      verify(() => pgRepo.getAll()).called(1);
    });

    test('Firebird: dispatches para repo correto', () async {
      when(() => fbRepo.getAll()).thenAnswer((_) async => rd.Success([fbCfg]));
      final outcome = await store.list(RemoteDatabaseType.firebird);
      expect(outcome.success, isTrue);
      verify(() => fbRepo.getAll()).called(1);
    });

    test('falha do repo vira outcome.failure', () async {
      when(
        () => sybaseRepo.getAll(),
      ).thenAnswer((_) async => rd.Failure(Exception('db error')));
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

    test('NotFoundFailure do repository mapeia para fileNotFound', () async {
      when(() => sybaseRepo.getAll()).thenAnswer(
        (_) async => const rd.Failure(
          NotFoundFailure(message: 'Configuração não encontrada'),
        ),
      );
      final outcome = await store.list(RemoteDatabaseType.sybase);
      expect(outcome.errorCode, ErrorCode.fileNotFound);
      expect(outcome.error, 'Configuração não encontrada');
      expect(outcome.error, isNot(contains('Failure(message:')));
    });
  });

  group('create', () {
    test(
      'Sybase: deserializa map -> entity, persiste, retorna config',
      () async {
        when(
          () => sybaseRepo.create(any()),
        ).thenAnswer((_) async => rd.Success(sybaseCfg));
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
      },
    );

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
      when(
        () => sybaseRepo.update(any()),
      ).thenAnswer((_) async => rd.Success(sybaseCfg));
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

    // ---- B12: merge de segredos vazios com valor armazenado ----
    //
    // Servidor nao reenvia password/cryptKey nos snapshots de list/get
    // por seguranca. Quando o cliente remoto reedita o formulario sem
    // reescrever esses campos, o payload chega com string vazia. Sem
    // merge, o repository sobrescreve o segredo com vazio (perda
    // silenciosa). Os testes abaixo asseguram que o valor existente e
    // preservado nesse cenario para os 4 SGBDs.

    test(
      'Sybase: update com password vazio preserva password existente',
      () async {
        when(
          () => sybaseRepo.getById('sb-1'),
        ).thenAnswer((_) async => rd.Success(sybaseCfg)); // password='p'
        SybaseConfig? captured;
        when(() => sybaseRepo.update(any())).thenAnswer((invocation) async {
          captured = invocation.positionalArguments.first as SybaseConfig;
          return rd.Success(sybaseCfg);
        });

        final outcome = await store.update(
          RemoteDatabaseType.sybase,
          const {
            'id': 'sb-1',
            'name': 'updated',
            'serverName': 's',
            'databaseName': 'd',
            'username': 'u',
            'password': '', // <-- cliente nao reescreveu
          },
        );

        expect(outcome.success, isTrue);
        expect(captured, isNotNull);
        expect(captured!.password, 'p'); // preservou existente
      },
    );

    test(
      'SqlServer: update com password vazio preserva password existente',
      () async {
        when(
          () => sqlRepo.getById('sql-1'),
        ).thenAnswer((_) async => rd.Success(sqlCfg));
        SqlServerConfig? captured;
        when(() => sqlRepo.update(any())).thenAnswer((invocation) async {
          captured = invocation.positionalArguments.first as SqlServerConfig;
          return rd.Success(sqlCfg);
        });

        await store.update(
          RemoteDatabaseType.sqlServer,
          const {
            'id': 'sql-1',
            'name': 'updated',
            'server': 's',
            'database': 'd',
            'username': 'u',
            'password': '',
          },
        );
        expect(captured!.password, 'p');
      },
    );

    test(
      'Postgres: update com password vazio preserva password existente',
      () async {
        when(
          () => pgRepo.getById('pg-1'),
        ).thenAnswer((_) async => rd.Success(pgCfg));
        PostgresConfig? captured;
        when(() => pgRepo.update(any())).thenAnswer((invocation) async {
          captured = invocation.positionalArguments.first as PostgresConfig;
          return rd.Success(pgCfg);
        });

        await store.update(
          RemoteDatabaseType.postgres,
          const {
            'id': 'pg-1',
            'name': 'updated',
            'host': 'h',
            'database': 'd',
            'username': 'u',
            'password': '',
          },
        );
        expect(captured!.password, 'p');
      },
    );

    test(
      'Firebird: update com password E cryptKey vazios preserva ambos os '
      'segredos armazenados (B12)',
      () async {
        final existing = fbCfg.copyWith(
          password: 'stored-pw',
          cryptKey: 'stored-ck',
        );
        when(
          () => fbRepo.getById('fb-1'),
        ).thenAnswer((_) async => rd.Success(existing));
        FirebirdConfig? captured;
        when(() => fbRepo.update(any())).thenAnswer((invocation) async {
          captured = invocation.positionalArguments.first as FirebirdConfig;
          return rd.Success(existing);
        });

        await store.update(
          RemoteDatabaseType.firebird,
          const {
            'id': 'fb-1',
            'name': 'updated',
            'host': 'h',
            'databaseFile': r'C:\data\db.fdb',
            'username': 'u',
            'password': '', // ambos vazios
            'cryptKey': '',
          },
        );

        expect(captured, isNotNull);
        expect(captured!.password, 'stored-pw');
        expect(captured!.cryptKey, 'stored-ck');
      },
    );

    test(
      'update com password preenchido NAO sobrescreve com valor armazenado '
      '(cliente realmente quis renovar a senha) e EVITA I/O extra a '
      'getById (early-return do descritor)',
      () async {
        SybaseConfig? captured;
        when(() => sybaseRepo.update(any())).thenAnswer((invocation) async {
          captured = invocation.positionalArguments.first as SybaseConfig;
          return rd.Success(sybaseCfg);
        });

        await store.update(
          RemoteDatabaseType.sybase,
          const {
            'id': 'sb-1',
            'name': 'updated',
            'serverName': 's',
            'databaseName': 'd',
            'username': 'u',
            'password': 'new-pw', // <-- cliente renovou
          },
        );

        expect(captured!.password, 'new-pw');
        // Early-return: nenhuma chave sensivel veio vazia, entao o
        // descriptor evita a chamada `getById` (otimizacao: sem I/O
        // extra contra repository).
        verifyNever(() => sybaseRepo.getById(any()));
      },
    );
  });

  group('delete', () {
    test('Sybase: dispatches delete pelo id', () async {
      when(
        () => sybaseRepo.delete('sb-1'),
      ).thenAnswer((_) async => const rd.Success('ok'));
      final outcome = await store.delete(RemoteDatabaseType.sybase, 'sb-1');
      expect(outcome.success, isTrue);
      verify(() => sybaseRepo.delete('sb-1')).called(1);
    });

    test('falha do repo vira outcome.failure', () async {
      when(
        () => sybaseRepo.delete('sb-1'),
      ).thenAnswer((_) async => rd.Failure(Exception('FK constraint')));
      final outcome = await store.delete(RemoteDatabaseType.sybase, 'sb-1');
      expect(outcome.success, isFalse);
      expect(outcome.errorCode, ErrorCode.unknown);
    });
  });
}
