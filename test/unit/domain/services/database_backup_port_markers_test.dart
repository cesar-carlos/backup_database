import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_database_backup_port.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSqlServerBackup extends Mock implements ISqlServerBackupService {}

class _MockPostgresBackup extends Mock implements IPostgresBackupService {}

class _MockSybaseBackup extends Mock implements ISybaseBackupService {}

void useSqlServerPort(IDatabaseBackupPort<SqlServerConfig> port) {
  expect(port, isNotNull);
}

void usePostgresPort(IDatabaseBackupPort<PostgresConfig> port) {
  expect(port, isNotNull);
}

void useSybasePort(IDatabaseBackupPort<SybaseConfig> port) {
  expect(port, isNotNull);
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      SqlServerConfig(
        id: 'fb',
        name: 'n',
        server: 's',
        database: DatabaseName('d'),
        username: 'u',
        password: 'p',
      ),
    );
    registerFallbackValue(
      PostgresConfig(
        name: 'n',
        host: 'h',
        database: DatabaseName('d'),
        username: 'u',
        password: 'p',
        id: 'fb',
        port: PortNumber(5432),
      ),
    );
    registerFallbackValue(
      SybaseConfig(
        id: 'fb',
        name: 'n',
        serverName: 'srv',
        databaseName: DatabaseName('d'),
        username: 'u',
        password: 'p',
        port: PortNumber(2638),
      ),
    );
    registerFallbackValue(
      BackupExecutionContext(outputDirectory: 'o', scheduleId: 's'),
    );
  });

  group('IDatabaseBackupPort marker interfaces', () {
    test('ISqlServerBackupService is assignable to generic port', () async {
      final mock = _MockSqlServerBackup();
      final cfg = SqlServerConfig(
        id: 'id-1',
        name: 'n',
        server: 's',
        database: DatabaseName('d'),
        username: 'u',
        password: 'p',
      );
      const result = BackupExecutionResult(
        backupPath: '/x.bak',
        fileSize: 1,
        duration: Duration.zero,
        databaseName: 'd',
      );
      when(
        () => mock.executeBackup(
          config: any(named: 'config'),
          context: any(named: 'context'),
        ),
      ).thenAnswer((_) async => const rd.Success(result));

      useSqlServerPort(mock);
      final ctx = BackupExecutionContext(
        outputDirectory: '/tmp',
        scheduleId: 'sched',
      );
      final r = await mock.executeBackup(config: cfg, context: ctx);
      expect(r.getOrNull(), same(result));
    });

    test('IPostgresBackupService is assignable to generic port', () async {
      final mock = _MockPostgresBackup();
      final cfg = PostgresConfig(
        name: 'n',
        host: 'h',
        database: DatabaseName('d'),
        username: 'u',
        password: 'p',
        id: 'id-pg',
        port: PortNumber(5432),
      );
      const execResult = BackupExecutionResult(
        backupPath: '/x.tar',
        fileSize: 2,
        duration: Duration.zero,
        databaseName: 'd',
      );
      when(
        () => mock.executeBackup(
          config: any(named: 'config'),
          context: any(named: 'context'),
        ),
      ).thenAnswer((_) async => const rd.Success(execResult));

      usePostgresPort(mock);
      final ctx = BackupExecutionContext(
        outputDirectory: '/tmp',
        scheduleId: 'sched',
      );
      final r = await mock.executeBackup(config: cfg, context: ctx);
      expect(r.getOrNull(), same(execResult));
    });

    test('ISybaseBackupService is assignable to generic port', () async {
      final mock = _MockSybaseBackup();
      final cfg = SybaseConfig(
        id: 'id-sy',
        name: 'n',
        serverName: 'srv',
        databaseName: DatabaseName('d'),
        username: 'u',
        password: 'p',
        port: PortNumber(2638),
      );
      const execResult = BackupExecutionResult(
        backupPath: '/x.db',
        fileSize: 3,
        duration: Duration.zero,
        databaseName: 'd',
      );
      when(
        () => mock.executeBackup(
          config: any(named: 'config'),
          context: any(named: 'context'),
        ),
      ).thenAnswer((_) async => const rd.Success(execResult));

      useSybasePort(mock);
      final ctx = BackupExecutionContext(
        outputDirectory: '/tmp',
        scheduleId: 'sched',
      );
      final r = await mock.executeBackup(config: cfg, context: ctx);
      expect(r.getOrNull(), same(execResult));
    });
  });
}
