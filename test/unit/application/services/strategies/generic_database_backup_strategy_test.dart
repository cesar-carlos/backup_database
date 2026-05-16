import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/backup_result_enricher.dart';
import 'package:backup_database/application/services/strategies/backup_validation_rule.dart';
import 'package:backup_database/application/services/strategies/generic_database_backup_strategy.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_database_backup_port.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSqlPort extends Mock
    implements IDatabaseBackupPort<SqlServerConfig> {}

BackupExecutionContext _testBuildContext({
  required Schedule schedule,
  required SqlServerConfig config,
  required String outputDirectory,
  required BackupType backupType,
  required String cancelTag,
}) {
  return BackupExecutionContext(
    outputDirectory: outputDirectory,
    scheduleId: schedule.id,
    backupType: backupType,
    cancelTag: cancelTag,
  );
}

GenericDatabaseBackupStrategy<SqlServerConfig> _makeStrategy({
  required IDatabaseBackupPort<SqlServerConfig> port,
  List<BackupValidationRule<SqlServerConfig>> rules =
      const <BackupValidationRule<SqlServerConfig>>[],
  List<BackupResultEnricher<SqlServerConfig>> enrichers =
      const <BackupResultEnricher<SqlServerConfig>>[],
}) {
  return GenericDatabaseBackupStrategy<SqlServerConfig>(
    databaseType: DatabaseType.sqlServer,
    port: port,
    rules: rules,
    enrichers: enrichers,
    buildContext: _testBuildContext,
  );
}

class _OkRule extends BackupValidationRule<SqlServerConfig> {
  @override
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SqlServerConfig config,
    required BackupType backupType,
  }) async {
    return const rd.Success(unit);
  }
}

class _FailRule extends BackupValidationRule<SqlServerConfig> {
  @override
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SqlServerConfig config,
    required BackupType backupType,
  }) async {
    return rd.Failure(Exception('rule failed'));
  }
}

class _SuffixEnricher extends BackupResultEnricher<SqlServerConfig> {
  @override
  Future<BackupExecutionResult> enrich(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SqlServerConfig config,
    required BackupType backupType,
    required BackupExecutionResult result,
  }) async {
    return BackupExecutionResult(
      backupPath: '${result.backupPath}.enriched',
      fileSize: result.fileSize + 1,
      duration: result.duration,
      databaseName: result.databaseName,
      metrics: result.metrics,
      executedBackupType: result.executedBackupType,
    );
  }
}

class _ThrowingEnricher extends BackupResultEnricher<SqlServerConfig> {
  @override
  Future<BackupExecutionResult> enrich(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SqlServerConfig config,
    required BackupType backupType,
    required BackupExecutionResult result,
  }) async {
    throw StateError('enricher boom');
  }
}

void main() {
  late SqlServerConfig sqlCfg;
  late Schedule schedule;
  const outputDirectory = r'C:\out';
  const cancelTag = '';

  setUpAll(() {
    registerFallbackValue(
      SqlServerConfig(
        id: 'fb',
        name: 'fb',
        server: 's',
        database: DatabaseName('db'),
        username: 'u',
        password: 'p',
        port: PortNumber(1433),
      ),
    );
    registerFallbackValue(
      BackupExecutionContext(
        outputDirectory: 'o',
        scheduleId: 'sid',
      ),
    );
  });

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
    schedule = Schedule(
      name: 'sch',
      databaseConfigId: 's1',
      databaseType: DatabaseType.sqlServer,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
    );
  });

  test('execute returns port result when rules pass', () async {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(port: port);
    const raw = BackupExecutionResult(
      backupPath: r'C:\out\a.bak',
      fileSize: 100,
      duration: Duration(seconds: 1),
      databaseName: 'db',
    );
    when(
      () => port.executeBackup(
        config: sqlCfg,
        context: any(named: 'context'),
      ),
    ).thenAnswer((_) async => const rd.Success(raw));

    final result = await strategy.execute(
      schedule: schedule,
      databaseConfig: sqlCfg,
      outputDirectory: outputDirectory,
      backupType: schedule.backupType,
      cancelTag: cancelTag,
    );

    expect(result.isSuccess(), isTrue);
    expect(result.getOrNull(), equals(raw));
    verify(
      () => port.executeBackup(
        config: sqlCfg,
        context: any(named: 'context'),
      ),
    ).called(1);
  });

  test('execute skips port when a validation rule fails', () async {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(port: port, rules: [_FailRule()]);

    final result = await strategy.execute(
      schedule: schedule,
      databaseConfig: sqlCfg,
      outputDirectory: outputDirectory,
      backupType: schedule.backupType,
      cancelTag: cancelTag,
    );

    expect(result.isError(), isTrue);
    verifyNever(
      () => port.executeBackup(
        config: any(named: 'config'),
        context: any(named: 'context'),
      ),
    );
  });

  test('execute runs rules in order before port', () async {
    final port = _MockSqlPort();
    final order = <int>[];
    final strategy = _makeStrategy(
      port: port,
      rules: [
        _RecordingRule(order, 1),
        _RecordingRule(order, 2),
      ],
    );
    const raw = BackupExecutionResult(
      backupPath: r'C:\x.bak',
      fileSize: 1,
      duration: Duration.zero,
      databaseName: 'db',
    );
    when(
      () => port.executeBackup(
        config: sqlCfg,
        context: any(named: 'context'),
      ),
    ).thenAnswer((_) async {
      order.add(3);
      return const rd.Success(raw);
    });

    await strategy.execute(
      schedule: schedule,
      databaseConfig: sqlCfg,
      outputDirectory: outputDirectory,
      backupType: schedule.backupType,
      cancelTag: cancelTag,
    );

    expect(order, [1, 2, 3]);
  });

  test('execute applies enrichers in order', () async {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(
      port: port,
      enrichers: [_SuffixEnricher(), _SuffixEnricher()],
    );
    const raw = BackupExecutionResult(
      backupPath: r'C:\base.bak',
      fileSize: 10,
      duration: Duration.zero,
      databaseName: 'db',
    );
    when(
      () => port.executeBackup(
        config: sqlCfg,
        context: any(named: 'context'),
      ),
    ).thenAnswer((_) async => const rd.Success(raw));

    final result = await strategy.execute(
      schedule: schedule,
      databaseConfig: sqlCfg,
      outputDirectory: outputDirectory,
      backupType: schedule.backupType,
      cancelTag: cancelTag,
    );

    expect(result.isSuccess(), isTrue);
    final out = result.getOrNull()!;
    expect(out.backupPath, r'C:\base.bak.enriched.enriched');
    expect(out.fileSize, 12);
  });

  test('execute returns failure when port fails', () async {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(port: port, rules: [_OkRule()]);
    when(
      () => port.executeBackup(
        config: sqlCfg,
        context: any(named: 'context'),
      ),
    ).thenAnswer((_) async => rd.Failure(Exception('port down')));

    final result = await strategy.execute(
      schedule: schedule,
      databaseConfig: sqlCfg,
      outputDirectory: outputDirectory,
      backupType: schedule.backupType,
      cancelTag: cancelTag,
    );

    expect(result.isError(), isTrue);
  });

  test('execute propagates when enricher throws', () async {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(
      port: port,
      enrichers: [_ThrowingEnricher()],
    );
    const raw = BackupExecutionResult(
      backupPath: r'C:\a.bak',
      fileSize: 1,
      duration: Duration.zero,
      databaseName: 'db',
    );
    when(
      () => port.executeBackup(
        config: sqlCfg,
        context: any(named: 'context'),
      ),
    ).thenAnswer((_) async => const rd.Success(raw));

    await expectLater(
      strategy.execute(
        schedule: schedule,
        databaseConfig: sqlCfg,
        outputDirectory: outputDirectory,
        backupType: schedule.backupType,
        cancelTag: cancelTag,
      ),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          'enricher boom',
        ),
      ),
    );
  });

  test('databaseType matches constructor', () {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(port: port);
    expect(strategy.databaseType, DatabaseType.sqlServer);
  });

  test('getDatabaseSizeBytes forwards config and timeout to port', () async {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(port: port);
    const timeout = Duration(seconds: 5);
    when(
      () => port.getDatabaseSizeBytes(
        config: sqlCfg,
        timeout: timeout,
      ),
    ).thenAnswer((_) async => const rd.Success(42_000));

    final result = await strategy.getDatabaseSizeBytes(
      databaseConfig: sqlCfg,
      timeout: timeout,
    );

    expect(result.isSuccess(), isTrue);
    expect(result.getOrNull(), 42_000);
    verify(
      () => port.getDatabaseSizeBytes(
        config: sqlCfg,
        timeout: timeout,
      ),
    ).called(1);
  });

  test('getDatabaseSizeBytes forwards null timeout', () async {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(port: port);
    when(
      () => port.getDatabaseSizeBytes(
        config: sqlCfg,
        timeout: null,
      ),
    ).thenAnswer((_) async => const rd.Success(1));

    final result = await strategy.getDatabaseSizeBytes(
      databaseConfig: sqlCfg,
    );

    expect(result.isSuccess(), isTrue);
    verify(
      () => port.getDatabaseSizeBytes(
        config: sqlCfg,
        timeout: null,
      ),
    ).called(1);
  });

  test('getDatabaseSizeBytes returns port failure', () async {
    final port = _MockSqlPort();
    final strategy = _makeStrategy(port: port);
    when(
      () => port.getDatabaseSizeBytes(
        config: sqlCfg,
        timeout: null,
      ),
    ).thenAnswer((_) async => rd.Failure(Exception('no size')));

    final result = await strategy.getDatabaseSizeBytes(
      databaseConfig: sqlCfg,
    );

    expect(result.isError(), isTrue);
  });
}

class _RecordingRule extends BackupValidationRule<SqlServerConfig> {
  _RecordingRule(this.order, this.id);

  final List<int> order;
  final int id;

  @override
  Future<rd.Result<void>> validate(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SqlServerConfig config,
    required BackupType backupType,
  }) async {
    order.add(id);
    return const rd.Success(unit);
  }
}
