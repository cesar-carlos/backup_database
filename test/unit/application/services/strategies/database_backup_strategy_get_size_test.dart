import 'package:backup_database/application/services/strategies/postgres_backup_strategy.dart';
import 'package:backup_database/application/services/strategies/sql_server_backup_strategy.dart';
import 'package:backup_database/application/services/strategies/sybase_backup_strategy_factory.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart';

class _MockSqlServerBackupService extends Mock
    implements ISqlServerBackupService {}

class _MockPostgresBackupService extends Mock
    implements IPostgresBackupService {}

class _MockSybaseBackupService extends Mock implements ISybaseBackupService {}

class _MockValidatePreflight extends Mock
    implements ValidateSybaseLogBackupPreflight {}

void main() {
  late SqlServerConfig sqlCfg;
  late PostgresConfig pgCfg;
  late SybaseConfig syCfg;

  setUp(() {
    sqlCfg = SqlServerConfig(
      id: 's1',
      name: 'n',
      server: 'localhost',
      database: DatabaseName('db'),
      username: 'u',
      password: 'p',
      port: PortNumber(1433),
    );
    pgCfg = PostgresConfig(
      name: 'pg',
      host: 'localhost',
      database: DatabaseName('db'),
      username: 'u',
      password: 'p',
    );
    syCfg = SybaseConfig(
      id: 'y1',
      name: 'sy',
      serverName: 'localhost',
      databaseName: DatabaseName('db'),
      username: 'u',
      password: 'p',
    );
  });

  test('SqlServerBackupStrategy forwards getDatabaseSizeBytes', () async {
    final mock = _MockSqlServerBackupService();
    final strategy = SqlServerBackupStrategy(mock);
    when(
      () => mock.getDatabaseSizeBytes(
        config: sqlCfg,
        timeout: const Duration(seconds: 2),
      ),
    ).thenAnswer((_) async => const Success(500));

    final result = await strategy.getDatabaseSizeBytes(
      databaseConfig: sqlCfg,
      timeout: const Duration(seconds: 2),
    );

    expect(result.getOrNull(), 500);
    verify(
      () => mock.getDatabaseSizeBytes(
        config: sqlCfg,
        timeout: const Duration(seconds: 2),
      ),
    ).called(1);
  });

  test('PostgresBackupStrategy forwards getDatabaseSizeBytes', () async {
    final mock = _MockPostgresBackupService();
    final strategy = PostgresBackupStrategy(mock);
    when(
      () => mock.getDatabaseSizeBytes(config: pgCfg),
    ).thenAnswer((_) async => const Success(9001));

    final result = await strategy.getDatabaseSizeBytes(
      databaseConfig: pgCfg,
    );

    expect(result.getOrNull(), 9001);
    verify(
      () => mock.getDatabaseSizeBytes(config: pgCfg),
    ).called(1);
  });

  test(
    'GenericDatabaseBackupStrategy<Sybase> forwards getDatabaseSizeBytes',
    () async {
      final mock = _MockSybaseBackupService();
      final preflight = _MockValidatePreflight();
      final strategy = SybaseBackupStrategyFactory.create(
        service: mock,
        validatePreflight: preflight,
      );
      when(
        () => mock.getDatabaseSizeBytes(config: syCfg),
      ).thenAnswer((_) async => const Success(42));

      final result = await strategy.getDatabaseSizeBytes(
        databaseConfig: syCfg,
      );

      expect(result.getOrNull(), 42);
      verify(
        () => mock.getDatabaseSizeBytes(config: syCfg),
      ).called(1);
    },
  );
}
