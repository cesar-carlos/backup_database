import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleDialogLabels.scheduleTypeName', () {
    test('maps schedule types to Portuguese labels', () {
      expect(
        ScheduleDialogLabels.scheduleTypeName(ScheduleType.daily),
        'Diário',
      );
      expect(
        ScheduleDialogLabels.scheduleTypeName(ScheduleType.weekly),
        'Semanal',
      );
      expect(
        ScheduleDialogLabels.scheduleTypeName(ScheduleType.monthly),
        'Mensal',
      );
      expect(
        ScheduleDialogLabels.scheduleTypeName(ScheduleType.interval),
        'Por Intervalo',
      );
    });
  });

  group('ScheduleDialogLabels.backupTypeDescription', () {
    test('PostgreSQL log mentions WAL capture', () {
      final desc = ScheduleDialogLabels.backupTypeDescription(
        DatabaseType.postgresql,
        BackupType.log,
      );
      expect(desc, contains('pg_receivewal'));
      expect(desc, contains('WAL'));
    });

    test('Firebird log description is Firebird-specific', () {
      final desc = ScheduleDialogLabels.backupTypeDescription(
        DatabaseType.firebird,
        BackupType.log,
      );
      expect(desc, isNot(contains('pg_receivewal')));
      expect(desc, isNot(contains('WAL')));
      expect(desc, contains('Firebird'));
      expect(desc, contains('nbackup'));
      expect(desc, contains('-B 1'));
    });

    test('Firebird full mentions nbackup and nbk', () {
      final desc = ScheduleDialogLabels.backupTypeDescription(
        DatabaseType.firebird,
        BackupType.full,
      );
      expect(desc, contains('nbackup'));
      expect(desc, contains('.nbk'));
    });

    test('Firebird fullSingle mentions gbak and fbk', () {
      final desc = ScheduleDialogLabels.backupTypeDescription(
        DatabaseType.firebird,
        BackupType.fullSingle,
      );
      expect(desc, contains('gbak'));
      expect(desc, contains('.fbk'));
    });

    test('Sybase differential explains conversion to incremental log', () {
      final desc = ScheduleDialogLabels.backupTypeDescription(
        DatabaseType.sybase,
        BackupType.differential,
      );
      expect(desc, contains('Sybase SQL Anywhere'));
      expect(desc, contains('Incremental'));
    });
  });
}
