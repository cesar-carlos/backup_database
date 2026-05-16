import 'package:backup_database/application/services/strategies/firebird_backup_strategy_factory.dart';
import 'package:backup_database/application/services/strategies/postgres_backup_strategy_factory.dart';
import 'package:backup_database/application/services/strategies/sql_server_backup_strategy_factory.dart';
import 'package:backup_database/application/services/strategies/sybase_backup_strategy_factory.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPg extends Mock implements IPostgresBackupService {}

class _MockFb extends Mock implements IFirebirdBackupService {}

class _MockSql extends Mock implements ISqlServerBackupService {}

class _MockSybase extends Mock implements ISybaseBackupService {}

class _MockPreflight extends Mock implements ValidateSybaseLogBackupPreflight {}

void main() {
  late PostgresConfig pgCfg;
  late SqlServerConfig sqlCfg;
  late SybaseConfig syCfg;
  late FirebirdConfig fbCfg;

  setUpAll(() {
    registerFallbackValue(
      FirebirdConfig(
        name: 'n',
        host: 'h',
        databaseFile: 'f',
        username: 'u',
        password: 'p',
      ),
    );
    registerFallbackValue(
      BackupExecutionContext(
        outputDirectory: 'o',
        scheduleId: 's',
      ),
    );
  });

  setUp(() {
    pgCfg = PostgresConfig(
      name: 'pg',
      host: 'localhost',
      database: DatabaseName('db'),
      username: 'u',
      password: 'p',
    );
    sqlCfg = SqlServerConfig(
      id: 's1',
      name: 'n',
      server: 'localhost',
      database: DatabaseName('db'),
      username: 'u',
      password: 'p',
      port: PortNumber(1433),
    );
    syCfg = SybaseConfig(
      name: 'sy',
      serverName: 'srv',
      databaseName: DatabaseName('db'),
      username: 'u',
      password: 'p',
    );
    fbCfg = FirebirdConfig(
      name: 'fb',
      host: 'localhost',
      databaseFile: r'C:\d.fdb',
      username: 'u',
      password: 'p',
    );
  });

  test('Postgres factory rejects converted types before service', () async {
    final mock = _MockPg();
    final strategy = PostgresBackupStrategyFactory.create(mock);
    final schedule = Schedule(
      name: 'sch',
      databaseConfigId: 'cfg',
      databaseType: DatabaseType.postgresql,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
    );
    final r = await strategy.execute(
      schedule: schedule,
      databaseConfig: pgCfg,
      outputDirectory: '/tmp',
      backupType: BackupType.convertedLog,
      cancelTag: 't',
    );
    expect(r.isError(), isTrue);
  });

  test('SqlServer factory rejects converted types before service', () async {
    final mock = _MockSql();
    final strategy = SqlServerBackupStrategyFactory.create(mock);
    final schedule = Schedule(
      name: 'sch',
      databaseConfigId: 'cfg',
      databaseType: DatabaseType.sqlServer,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
    );
    final r = await strategy.execute(
      schedule: schedule,
      databaseConfig: sqlCfg,
      outputDirectory: '/tmp',
      backupType: BackupType.convertedFullSingle,
      cancelTag: 't',
    );
    expect(r.isError(), isTrue);
  });

  test('Sybase factory rejects differential before service', () async {
    final mock = _MockSybase();
    final preflight = _MockPreflight();
    final strategy = SybaseBackupStrategyFactory.create(
      service: mock,
      validatePreflight: preflight,
    );
    final schedule = Schedule(
      name: 'sch',
      databaseConfigId: 'cfg',
      databaseType: DatabaseType.sybase,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
    );
    final r = await strategy.execute(
      schedule: schedule,
      databaseConfig: syCfg,
      outputDirectory: '/tmp',
      backupType: BackupType.differential,
      cancelTag: 't',
    );
    expect(r.isError(), isTrue);
  });

  test('Firebird factory rejects log before service', () async {
    final mock = _MockFb();
    final strategy = FirebirdBackupStrategyFactory.create(mock);
    final schedule = Schedule(
      name: 'sch',
      databaseConfigId: 'cfg',
      databaseType: DatabaseType.firebird,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
    );
    final r = await strategy.execute(
      schedule: schedule,
      databaseConfig: fbCfg,
      outputDirectory: '/tmp',
      backupType: BackupType.log,
      cancelTag: 't',
    );
    expect(r.isError(), isTrue);
    verifyNever(
      () => mock.executeBackup(
        config: any(named: 'config'),
        context: any(named: 'context'),
      ),
    );
  });
}
