import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_firebird_config_repository.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/services/i_sql_script_execution_service.dart';
import 'package:backup_database/infrastructure/scripts/backup_script_orchestrator_impl.dart';
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

class _MockSqlScriptExecutionService extends Mock
    implements ISqlScriptExecutionService {}

class _MockBackupLogRepository extends Mock implements IBackupLogRepository {}

void main() {
  group('BackupScriptOrchestratorImpl', () {
    const historyId = 'hist-1';
    const scriptBody = r'SELECT 1 FROM RDB$DATABASE;';

    late _MockSqlServerConfigRepository sqlRepo;
    late _MockSybaseConfigRepository sybaseRepo;
    late _MockPostgresConfigRepository postgresRepo;
    late _MockFirebirdConfigRepository firebirdRepo;
    late _MockSqlScriptExecutionService scriptService;
    late _MockBackupLogRepository logRepo;
    late BackupScriptOrchestratorImpl orchestrator;

    setUpAll(() {
      registerFallbackValue(
        BackupLog(
          level: LogLevel.info,
          category: LogCategory.execution,
          message: 'fallback',
          backupHistoryId: historyId,
        ),
      );
    });

    setUp(() {
      sqlRepo = _MockSqlServerConfigRepository();
      sybaseRepo = _MockSybaseConfigRepository();
      postgresRepo = _MockPostgresConfigRepository();
      firebirdRepo = _MockFirebirdConfigRepository();
      scriptService = _MockSqlScriptExecutionService();
      logRepo = _MockBackupLogRepository();
      orchestrator = const BackupScriptOrchestratorImpl();

      when(() => logRepo.create(any())).thenAnswer(
        (invocation) async => rd.Success(
          invocation.positionalArguments.first as BackupLog,
        ),
      );
    });

    test(
      'executePostBackupScript loads Firebird config and passes it to '
      'executeScript',
      () async {
        final fbConfig = FirebirdConfig(
          id: 'fb-1',
          name: 'fb',
          host: 'localhost',
          databaseFile: r'C:\data\app.fdb',
          username: 'sysdba',
          password: 'x',
        );
        final schedule = Schedule(
          id: 'sch-1',
          name: 'Backup FB',
          databaseConfigId: fbConfig.id,
          databaseType: DatabaseType.firebird,
          scheduleType: ScheduleType.daily.name,
          scheduleConfig: '{}',
          destinationIds: const <String>[],
          backupFolder: r'C:\backup',
          postBackupScript: scriptBody,
          verifyTimeout: Duration.zero,
        );

        when(
          () => firebirdRepo.getById(fbConfig.id),
        ).thenAnswer((_) async => rd.Success(fbConfig));
        when(
          () => scriptService.executeScript(
            databaseType: DatabaseType.firebird,
            sqlServerConfig: null,
            sybaseConfig: null,
            postgresConfig: null,
            firebirdConfig: fbConfig,
            script: scriptBody,
          ),
        ).thenAnswer((_) async => const rd.Success(rd.unit));

        final result = await orchestrator.executePostBackupScript(
          historyId: historyId,
          schedule: schedule,
          sqlServerConfigRepository: sqlRepo,
          sybaseConfigRepository: sybaseRepo,
          postgresConfigRepository: postgresRepo,
          firebirdConfigRepository: firebirdRepo,
          scriptService: scriptService,
          logRepository: logRepo,
        );

        expect(result.isSuccess(), isTrue);
        verify(() => firebirdRepo.getById(fbConfig.id)).called(1);
        verifyNever(() => sqlRepo.getById(any()));
        verifyNever(() => sybaseRepo.getById(any()));
        verifyNever(() => postgresRepo.getById(any()));
        verify(
          () => scriptService.executeScript(
            databaseType: DatabaseType.firebird,
            sqlServerConfig: null,
            sybaseConfig: null,
            postgresConfig: null,
            firebirdConfig: fbConfig,
            script: scriptBody,
          ),
        ).called(1);
        verify(() => logRepo.create(any())).called(2);
      },
    );
  });
}
