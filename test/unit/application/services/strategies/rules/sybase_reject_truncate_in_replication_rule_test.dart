import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/rules/sybase_reject_truncate_in_replication_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rule = SybaseRejectTruncateInReplicationRule();

  test('allows truncate log when not replication environment', () async {
    final config = SybaseConfig(
      name: 'sy',
      serverName: 'srv',
      databaseName: DatabaseName('db'),
      username: 'u',
      password: 'p',
    );
    final schedule = SybaseBackupSchedule(
      name: 'sch',
      databaseConfigId: 'cfg',
      databaseType: DatabaseType.sybase,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
      backupType: BackupType.log,
      sybaseBackupOptions: const SybaseBackupOptions(
        logBackupMode: SybaseLogBackupMode.truncate,
      ),
    );
    final r = await rule.validate(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.log,
    );
    expect(r.isSuccess(), isTrue);
  });

  test('blocks truncate log in replication environment', () async {
    final config = SybaseConfig(
      name: 'sy',
      serverName: 'srv',
      databaseName: DatabaseName('db'),
      username: 'u',
      password: 'p',
      isReplicationEnvironment: true,
    );
    final schedule = SybaseBackupSchedule(
      name: 'sch',
      databaseConfigId: 'cfg',
      databaseType: DatabaseType.sybase,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
      backupType: BackupType.log,
      sybaseBackupOptions: const SybaseBackupOptions(
        logBackupMode: SybaseLogBackupMode.truncate,
      ),
    );
    final r = await rule.validate(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.log,
    );
    expect(r.isError(), isTrue);
  });
}
