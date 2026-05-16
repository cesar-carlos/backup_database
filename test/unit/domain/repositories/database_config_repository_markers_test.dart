import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_database_config_repository.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSqlServerRepo extends Mock implements ISqlServerConfigRepository {}

class _MockSybaseRepo extends Mock implements ISybaseConfigRepository {}

class _MockPostgresRepo extends Mock implements IPostgresConfigRepository {}

Future<rd.Result<List<SqlServerConfig>>> _answerEmptySqlList(
  Invocation _,
) => Future.value(const rd.Success(<SqlServerConfig>[]));

Future<rd.Result<List<SybaseConfig>>> _answerEmptySybaseList(
  Invocation _,
) => Future.value(const rd.Success(<SybaseConfig>[]));

Future<rd.Result<List<PostgresConfig>>> _answerEmptyPostgresList(
  Invocation _,
) => Future.value(const rd.Success(<PostgresConfig>[]));

void useSqlGeneric(IDatabaseConfigRepository<SqlServerConfig> repo) {
  expect(repo, isNotNull);
}

void useSybaseGeneric(IDatabaseConfigRepository<SybaseConfig> repo) {
  expect(repo, isNotNull);
}

void usePostgresGeneric(IDatabaseConfigRepository<PostgresConfig> repo) {
  expect(repo, isNotNull);
}

void main() {
  group('IDatabaseConfigRepository marker interfaces', () {
    test('ISqlServerConfigRepository is assignable to generic port', () async {
      final mock = _MockSqlServerRepo();
      // ignore: unnecessary_lambdas -- mocktail when() needs a capture thunk
      when(() => mock.getAll()).thenAnswer(_answerEmptySqlList);

      useSqlGeneric(mock);
      final result = await mock.getAll();
      expect(result.isSuccess(), isTrue);
    });

    test('ISybaseConfigRepository is assignable to generic port', () async {
      final mock = _MockSybaseRepo();
      // ignore: unnecessary_lambdas -- mocktail when() needs a capture thunk
      when(() => mock.getAll()).thenAnswer(_answerEmptySybaseList);

      useSybaseGeneric(mock);
      final result = await mock.getAll();
      expect(result.isSuccess(), isTrue);
    });

    test('IPostgresConfigRepository is assignable to generic port', () async {
      final mock = _MockPostgresRepo();
      // ignore: unnecessary_lambdas -- mocktail when() needs a capture thunk
      when(() => mock.getAll()).thenAnswer(_answerEmptyPostgresList);

      usePostgresGeneric(mock);
      final result = await mock.getAll();
      expect(result.isSuccess(), isTrue);
    });

    test('getById is declared on generic port', () async {
      final mock = _MockSqlServerRepo();
      final cfg = SqlServerConfig(
        id: 'id-1',
        name: 'n',
        server: 's',
        database: DatabaseName('d'),
        username: 'u',
        password: 'p',
      );
      Future<rd.Result<SqlServerConfig>> answerById(Invocation _) =>
          Future.value(rd.Success(cfg));
      when(() => mock.getById('id-1')).thenAnswer(answerById);

      final r = await mock.getById('id-1');
      expect(r.getOrNull(), same(cfg));
    });
  });
}
