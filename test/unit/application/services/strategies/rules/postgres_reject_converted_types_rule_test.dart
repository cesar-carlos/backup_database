import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/rules/postgres_reject_converted_types_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rule = PostgresRejectConvertedTypesRule();
  final config = PostgresConfig(
    name: 'pg',
    host: 'localhost',
    database: DatabaseName('db'),
    username: 'u',
    password: 'p',
  );
  final schedule = Schedule(
    name: 'sch',
    databaseConfigId: 'cfg',
    databaseType: DatabaseType.postgresql,
    scheduleType: 'daily',
    scheduleConfig: '{}',
    destinationIds: const [],
    backupFolder: 'bf',
  );

  test('allows native backup types', () async {
    final r = await rule.validate(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.full,
    );
    expect(r.isSuccess(), isTrue);
  });

  test('rejects converted differential', () async {
    final r = await rule.validate(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.convertedDifferential,
    );
    expect(r.isError(), isTrue);
  });
}
