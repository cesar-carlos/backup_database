import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/rules/sql_server_reject_converted_types_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rule = SqlServerRejectConvertedTypesRule();
  final config = SqlServerConfig(
    id: 's1',
    name: 'n',
    server: 'localhost',
    database: DatabaseName('db'),
    username: 'u',
    password: 'p',
    port: PortNumber(1433),
  );
  final schedule = Schedule(
    name: 'sch',
    databaseConfigId: 'cfg',
    databaseType: DatabaseType.sqlServer,
    scheduleType: 'daily',
    scheduleConfig: '{}',
    destinationIds: const [],
    backupFolder: 'bf',
  );

  test('allows full backup', () async {
    final r = await rule.validate(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.full,
    );
    expect(r.isSuccess(), isTrue);
  });

  test('rejects converted log', () async {
    final r = await rule.validate(
      BackupPipelineContext(),
      schedule: schedule,
      config: config,
      backupType: BackupType.convertedLog,
    );
    expect(r.isError(), isTrue);
  });
}
