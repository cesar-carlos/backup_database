import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const backupTimeout = Duration(hours: 2);
  const verifyTimeout = Duration(minutes: 30);

  ScheduleDialogDraft draft({
    required DatabaseType databaseType,
    String? id,
    BackupType backupType = BackupType.full,
    bool truncateLog = true,
    SqlServerBackupOptions? sqlServerBackupOptions,
    SybaseBackupOptions? sybaseBackupOptions,
    int? firebirdNbackupPhysicalLevel,
    bool? isConvertedDifferential,
  }) {
    return ScheduleDialogDraft(
      id: id,
      name: 'Nightly',
      databaseConfigId: 'cfg-1',
      databaseType: databaseType,
      scheduleTypeString: 'daily',
      scheduleConfigJson: '{"hour":2,"minute":0}',
      destinationIds: const ['dest-1'],
      backupFolder: r'C:\Backups',
      backupType: backupType,
      compressBackup: true,
      compressionFormat: CompressionFormat.zip,
      enabled: true,
      enableChecksum: false,
      verifyAfterBackup: false,
      verifyPolicy: VerifyPolicy.bestEffort,
      truncateLog: truncateLog,
      backupTimeout: backupTimeout,
      verifyTimeout: verifyTimeout,
      sqlServerBackupOptions: sqlServerBackupOptions,
      sybaseBackupOptions: sybaseBackupOptions,
      firebirdNbackupPhysicalLevel: firebirdNbackupPhysicalLevel,
      isConvertedDifferential: isConvertedDifferential,
    );
  }

  group('ScheduleDialogDraft.toSchedule', () {
    test('SQL Server maps options and existing converted flag', () {
      const options = SqlServerBackupOptions(
        compression: true,
        stripingCount: 2,
      );
      final schedule = draft(
        id: 'sql-1',
        databaseType: DatabaseType.sqlServer,
        sqlServerBackupOptions: options,
        isConvertedDifferential: true,
        firebirdNbackupPhysicalLevel: 3,
      ).toSchedule();

      expect(schedule.id, 'sql-1');
      expect(schedule.sqlServerBackupOptions, options);
      expect(schedule.sybaseBackupOptions, isNull);
      expect(schedule.firebirdNbackupPhysicalLevel, isNull);
      expect(schedule.isConvertedDifferential, isTrue);
      expect(schedule.truncateLog, isTrue);
    });

    test('SQL Server defaults converted flag when existing is null', () {
      final schedule = draft(
        databaseType: DatabaseType.sqlServer,
        sqlServerBackupOptions: const SqlServerBackupOptions(),
      ).toSchedule();

      expect(schedule.isConvertedDifferential, isFalse);
    });

    test('Sybase uses truncate log mode and backup-type converted flag', () {
      final schedule = draft(
        id: 'syb-1',
        databaseType: DatabaseType.sybase,
        backupType: BackupType.differential,
        truncateLog: false,
        sybaseBackupOptions: const SybaseBackupOptions(
          serverSide: true,
          blockSize: 8,
        ),
      ).toSchedule();

      expect(schedule.truncateLog, isFalse);
      expect(
        schedule.sybaseBackupOptions?.logBackupMode,
        SybaseLogBackupMode.only,
      );
      expect(schedule.sybaseBackupOptions?.serverSide, isTrue);
      expect(schedule.sybaseBackupOptions?.blockSize, 8);
      expect(schedule.sqlServerBackupOptions, isNull);
      expect(schedule.firebirdNbackupPhysicalLevel, isNull);
      expect(schedule.isConvertedDifferential, isTrue);
    });

    test('Sybase preserves existing false converted flag', () {
      final schedule = draft(
        databaseType: DatabaseType.sybase,
        backupType: BackupType.differential,
        sybaseBackupOptions: const SybaseBackupOptions(
          logBackupMode: SybaseLogBackupMode.truncate,
        ),
        isConvertedDifferential: false,
      ).toSchedule();

      expect(schedule.isConvertedDifferential, isFalse);
      expect(schedule.truncateLog, isTrue);
    });

    test('Firebird maps nbackup level and omits engine options', () {
      final schedule = draft(
        id: 'fb-1',
        databaseType: DatabaseType.firebird,
        firebirdNbackupPhysicalLevel: 2,
        sqlServerBackupOptions: const SqlServerBackupOptions(),
        isConvertedDifferential: true,
      ).toSchedule();

      expect(schedule.firebirdNbackupPhysicalLevel, 2);
      expect(schedule.sqlServerBackupOptions, isNull);
      expect(schedule.sybaseBackupOptions, isNull);
      expect(schedule.isConvertedDifferential, isFalse);
    });
  });
}
