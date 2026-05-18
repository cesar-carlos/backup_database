import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/repositories/i_firebird_config_repository.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/use_cases/backup/get_database_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSqlServerConfigRepository extends Mock
    implements ISqlServerConfigRepository {}

class _MockSybaseConfigRepository extends Mock
    implements ISybaseConfigRepository {}

class _MockPostgresConfigRepository extends Mock
    implements IPostgresConfigRepository {}

class _MockFirebirdConfigRepository extends Mock
    implements IFirebirdConfigRepository {}

void main() {
  group('GetDatabaseConfig', () {
    late _MockSqlServerConfigRepository sqlRepo;
    late _MockSybaseConfigRepository sybaseRepo;
    late _MockPostgresConfigRepository postgresRepo;
    late _MockFirebirdConfigRepository firebirdRepo;
    late GetDatabaseConfig useCase;

    setUp(() {
      sqlRepo = _MockSqlServerConfigRepository();
      sybaseRepo = _MockSybaseConfigRepository();
      postgresRepo = _MockPostgresConfigRepository();
      firebirdRepo = _MockFirebirdConfigRepository();
      useCase = GetDatabaseConfig(
        sqlServerConfigRepository: sqlRepo,
        sybaseConfigRepository: sybaseRepo,
        postgresConfigRepository: postgresRepo,
        firebirdConfigRepository: firebirdRepo,
      );
    });

    test('should return Firebird config when type is firebird', () async {
      const configId = 'fb-config-1';
      final config = FirebirdConfig(
        id: configId,
        name: 'fb',
        host: 'localhost',
        databaseFile: r'C:\data\app.fdb',
        username: 'sysdba',
        password: 'x',
      );
      when(
        () => firebirdRepo.getById(configId),
      ).thenAnswer((_) async => rd.Success(config));

      final result = await useCase(configId, DatabaseType.firebird);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), same(config));
      verify(() => firebirdRepo.getById(configId)).called(1);
      verifyNever(() => sqlRepo.getById(any()));
      verifyNever(() => sybaseRepo.getById(any()));
      verifyNever(() => postgresRepo.getById(any()));
    });

    test('should propagate failure from Firebird repository', () async {
      const configId = 'missing-fb';
      when(() => firebirdRepo.getById(configId)).thenAnswer(
        (_) async => const rd.Failure(
          NotFoundFailure(message: 'Firebird config not found'),
        ),
      );

      final result = await useCase(configId, DatabaseType.firebird);

      expect(result.isError(), isTrue);
      verify(() => firebirdRepo.getById(configId)).called(1);
    });
  });
}
