import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/rules/sybase_log_backup_preflight_rule.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart';

class _MockPreflight extends Mock implements ValidateSybaseLogBackupPreflight {}

void main() {
  late Schedule schedule;
  late SybaseConfig config;

  setUpAll(() {
    schedule = Schedule(
      name: 'sch',
      databaseConfigId: 'cfg',
      databaseType: DatabaseType.sybase,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const [],
      backupFolder: 'bf',
      backupType: BackupType.log,
    );
    registerFallbackValue(schedule);
    config = SybaseConfig(
      name: 'sy',
      serverName: 'srv',
      databaseName: DatabaseName('db'),
      username: 'u',
      password: 'p',
    );
  });

  test('skips preflight when backup is not log', () async {
    final mock = _MockPreflight();
    final rule = SybaseLogBackupPreflightRule(mock);
    final ctx = BackupPipelineContext();
    final r = await rule.validate(
      ctx,
      schedule: schedule,
      config: config,
      backupType: BackupType.full,
    );
    expect(r.isSuccess(), isTrue);
    expect(ctx.sybaseLogPreflight, isNull);
    verifyNever(() => mock(any()));
  });

  test('stores preflight on success for log backup', () async {
    final mock = _MockPreflight();
    final rule = SybaseLogBackupPreflightRule(mock);
    const preflight = SybaseLogBackupPreflightResult(canProceed: true);
    when(
      () => mock(schedule),
    ).thenAnswer((_) async => const Success(preflight));
    final ctx = BackupPipelineContext();
    final r = await rule.validate(
      ctx,
      schedule: schedule,
      config: config,
      backupType: BackupType.log,
    );
    expect(r.isSuccess(), isTrue);
    expect(ctx.sybaseLogPreflight, preflight);
    verify(() => mock(schedule)).called(1);
  });
}
