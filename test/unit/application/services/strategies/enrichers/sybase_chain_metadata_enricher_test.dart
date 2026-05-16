import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/enrichers/sybase_chain_metadata_enricher.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'enrich adds chain keys when preflight has baseFull and sequence',
    () async {
      final started = DateTime.utc(2024, 1, 2);
      final baseFull = BackupHistory(
        databaseName: 'db',
        databaseType: 'sybase',
        backupPath: '/x',
        fileSize: 1,
        status: BackupStatus.success,
        startedAt: started,
        finishedAt: started.add(const Duration(minutes: 1)),
      );
      final context = BackupPipelineContext()
        ..sybaseLogPreflight = SybaseLogBackupPreflightResult(
          canProceed: true,
          baseFull: baseFull,
          nextLogSequence: 3,
        );
      const flags = BackupFlags(
        compression: false,
        verifyPolicy: 'bestEffort',
        stripingCount: 0,
        withChecksum: false,
        stopOnError: false,
      );
      const metrics = BackupMetrics(
        totalDuration: Duration.zero,
        backupDuration: Duration.zero,
        verifyDuration: Duration.zero,
        backupSizeBytes: 0,
        backupSpeedMbPerSec: 0,
        backupType: 'log',
        flags: flags,
        sybaseOptions: {'existing': 1},
      );
      final enricher = SybaseChainMetadataEnricher();
      final config = SybaseConfig(
        name: 'n',
        serverName: 'srv',
        databaseName: DatabaseName('db'),
        username: 'u',
        password: 'p',
      );
      final schedule = Schedule(
        name: 'sch',
        databaseConfigId: 'cfg',
        databaseType: DatabaseType.sybase,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const [],
        backupFolder: 'bf',
        backupType: BackupType.log,
      );
      const input = BackupExecutionResult(
        backupPath: '/out',
        fileSize: 10,
        duration: Duration(seconds: 1),
        databaseName: 'db',
        metrics: metrics,
      );

      final out = await enricher.enrich(
        context,
        schedule: schedule,
        config: config,
        backupType: BackupType.log,
        result: input,
      );

      expect(out.metrics?.sybaseOptions?['baseFullId'], baseFull.id);
      expect(out.metrics?.sybaseOptions?['logSequence'], 3);
      expect(out.metrics?.sybaseOptions?['existing'], 1);
    },
  );

  test('enrich is no-op when preflight is null', () async {
    final enricher = SybaseChainMetadataEnricher();
    final config = SybaseConfig(
      name: 'n',
      serverName: 'srv',
      databaseName: DatabaseName('db'),
      username: 'u',
      password: 'p',
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
    const input = BackupExecutionResult(
      backupPath: '/out',
      fileSize: 0,
      duration: Duration.zero,
      databaseName: 'db',
    );
    final out = await enricher.enrich(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.full,
      result: input,
    );
    expect(identical(out, input), isTrue);
  });
}
