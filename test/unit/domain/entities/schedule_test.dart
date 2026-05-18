import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Schedule', () {
    test('equality compares by id only', () {
      final a = Schedule(
        id: 'same-id',
        name: 'A',
        databaseConfigId: 'cfg',
        databaseType: DatabaseType.sqlServer,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const ['d1'],
        backupFolder: r'C:\b',
      );
      final b = Schedule(
        id: 'same-id',
        name: 'B',
        databaseConfigId: 'cfg2',
        databaseType: DatabaseType.sybase,
        scheduleType: 'weekly',
        scheduleConfig: '{}',
        destinationIds: const ['d2'],
        backupFolder: r'D:\b',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith replaces fields and preserves sqlServerBackupOptions', () {
      const sqlOptions = SqlServerBackupOptions(compression: true);
      final schedule = Schedule(
        id: 'id-1',
        name: 'Original',
        databaseConfigId: 'cfg',
        databaseType: DatabaseType.sqlServer,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const ['d1'],
        backupFolder: r'C:\b',
        sqlServerBackupOptions: sqlOptions,
      );

      final updated = schedule.copyWith(
        name: 'Updated',
        backupType: BackupType.differential,
      );

      expect(updated.name, 'Updated');
      expect(updated.backupType, BackupType.differential);
      expect(updated.sqlServerBackupOptions, sqlOptions);
    });

    test('factory assigns id and default compressionFormat', () {
      final schedule = Schedule(
        name: 'New',
        databaseConfigId: 'cfg',
        databaseType: DatabaseType.postgresql,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const [],
        backupFolder: '',
      );

      expect(schedule.id, isNotEmpty);
      expect(schedule.compressionFormat, CompressionFormat.none);
      expect(schedule.verifyPolicy, VerifyPolicy.bestEffort);
    });

    test('resolvedSybaseBackupOptions uses safe defaults when null', () {
      final schedule = Schedule(
        name: 'Sybase',
        databaseConfigId: 'cfg',
        databaseType: DatabaseType.sybase,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const [],
        backupFolder: '',
      );

      expect(
        schedule.resolvedSybaseBackupOptions,
        SybaseBackupOptions.safeDefaults,
      );
    });
  });
}
