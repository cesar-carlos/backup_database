import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/rules/sybase_reject_differential_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rule = SybaseRejectDifferentialRule();
  final config = SybaseConfig(
    name: 'sy',
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

  test('allows log backup', () async {
    final r = await rule.validate(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.log,
    );
    expect(r.isSuccess(), isTrue);
  });

  test('rejects differential', () async {
    final r = await rule.validate(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.differential,
    );
    expect(r.isError(), isTrue);
  });
}
