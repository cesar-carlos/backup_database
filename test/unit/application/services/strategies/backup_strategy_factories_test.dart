import 'package:backup_database/application/services/strategies/firebird_backup_strategy_factory.dart';
import 'package:backup_database/application/services/strategies/postgres_backup_strategy_factory.dart';
import 'package:backup_database/application/services/strategies/sql_server_backup_strategy_factory.dart';
import 'package:backup_database/application/services/strategies/sybase_backup_strategy_factory.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

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
      SqlServerConfig(
        name: 'n',
        server: 'h',
        database: DatabaseName('db'),
        username: 'u',
        password: 'p',
      ),
    );
    registerFallbackValue(
      const BackupExecutionContext(
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

  test(
    'SqlServer factory forwards schedule timeouts and options to service',
    () async {
      final mock = _MockSql();
      final captured = <BackupExecutionContext>[];
      when(
        () => mock.executeBackup(
          config: any(named: 'config'),
          context: any(named: 'context'),
        ),
      ).thenAnswer((invocation) async {
        captured.add(
          invocation.namedArguments[#context]! as BackupExecutionContext,
        );
        return const rd.Success(
          BackupExecutionResult(
            backupPath: r'C:\x.bak',
            fileSize: 16,
            duration: Duration.zero,
            databaseName: 'db',
          ),
        );
      });
      final strategy = SqlServerBackupStrategyFactory.create(mock);
      const sqlOptions = SqlServerBackupOptions(
        compression: true,
        statsPercent: 5,
      );
      final schedule = Schedule(
        name: 'sch',
        databaseConfigId: 'cfg',
        databaseType: DatabaseType.sqlServer,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const [],
        backupFolder: 'bf',
        truncateLog: false,
        enableChecksum: true,
        verifyAfterBackup: true,
        verifyPolicy: VerifyPolicy.strict,
        backupTimeout: const Duration(hours: 5),
        verifyTimeout: const Duration(hours: 1),
        sqlServerBackupOptions: sqlOptions,
      );

      final r = await strategy.execute(
        schedule: schedule,
        databaseConfig: sqlCfg,
        outputDirectory: '/tmp',
        backupType: BackupType.full,
        cancelTag: 'backup-h1',
      );

      expect(r.isSuccess(), isTrue);
      final ctx = captured.single;
      // Achado A.1 da auditoria: antes desse fix, os timeouts do schedule
      // eram descartados pelo factory e o service caía nos defaults
      // hardcoded (2h backup / 30min verify).
      expect(ctx.backupTimeout, const Duration(hours: 5));
      expect(ctx.verifyTimeout, const Duration(hours: 1));
      expect(ctx.truncateLog, isFalse);
      expect(ctx.enableChecksum, isTrue);
      expect(ctx.verifyAfterBackup, isTrue);
      expect(ctx.verifyPolicy, VerifyPolicy.strict);
      expect(ctx.sqlServerBackupOptions, same(sqlOptions));
      expect(ctx.cancelTag, 'backup-h1');
    },
  );

  test('Firebird factory forwards log to service after validation', () async {
    final mock = _MockFb();
    final captured = <BackupExecutionContext>[];
    when(
      () => mock.executeBackup(
        config: any(named: 'config'),
        context: any(named: 'context'),
      ),
    ).thenAnswer((invocation) async {
      captured.add(
        invocation.namedArguments[#context]! as BackupExecutionContext,
      );
      return const rd.Success(
        BackupExecutionResult(
          backupPath: '/x.nbk',
          fileSize: 8,
          duration: Duration.zero,
          databaseName: 'd',
          executedBackupType: BackupType.differential,
        ),
      );
    });
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
    expect(r.isSuccess(), isTrue);
    expect(captured.single.backupType, BackupType.log);
    verify(
      () => mock.executeBackup(
        config: fbCfg,
        context: any(named: 'context'),
      ),
    ).called(1);
  });
}
