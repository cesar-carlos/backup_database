import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_backup_type_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeBackupTypeForDatabase', () {
    test(
      'coerces fullSingle to full when SGBD is not postgres or firebird',
      () {
        expect(
          normalizeBackupTypeForDatabase(
            DatabaseType.sqlServer,
            BackupType.fullSingle,
          ),
          BackupType.full,
        );
        expect(
          normalizeBackupTypeForDatabase(
            DatabaseType.sybase,
            BackupType.fullSingle,
          ),
          BackupType.full,
        );
      },
    );

    test('preserves fullSingle for postgres and firebird', () {
      expect(
        normalizeBackupTypeForDatabase(
          DatabaseType.postgresql,
          BackupType.fullSingle,
        ),
        BackupType.fullSingle,
      );
      expect(
        normalizeBackupTypeForDatabase(
          DatabaseType.firebird,
          BackupType.fullSingle,
        ),
        BackupType.fullSingle,
      );
    });

    test('coerces sybase differential to full', () {
      expect(
        normalizeBackupTypeForDatabase(
          DatabaseType.sybase,
          BackupType.differential,
        ),
        BackupType.full,
      );
    });

    test('preserves firebird differential', () {
      expect(
        normalizeBackupTypeForDatabase(
          DatabaseType.firebird,
          BackupType.differential,
        ),
        BackupType.differential,
      );
    });

    test('maps firebird convertedFullSingle to fullSingle', () {
      expect(
        normalizeBackupTypeForDatabase(
          DatabaseType.firebird,
          BackupType.convertedFullSingle,
        ),
        BackupType.fullSingle,
      );
    });

    test('preserves converted types for postgres', () {
      expect(
        normalizeBackupTypeForDatabase(
          DatabaseType.postgresql,
          BackupType.convertedFullSingle,
        ),
        BackupType.convertedFullSingle,
      );
      expect(
        normalizeBackupTypeForDatabase(
          DatabaseType.postgresql,
          BackupType.convertedDifferential,
        ),
        BackupType.convertedDifferential,
      );
      expect(
        normalizeBackupTypeForDatabase(
          DatabaseType.postgresql,
          BackupType.convertedLog,
        ),
        BackupType.convertedLog,
      );
    });

    test('preserves full and log for sybase', () {
      expect(
        normalizeBackupTypeForDatabase(DatabaseType.sybase, BackupType.full),
        BackupType.full,
      );
      expect(
        normalizeBackupTypeForDatabase(DatabaseType.sybase, BackupType.log),
        BackupType.log,
      );
    });
  });
}
