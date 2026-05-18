import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupHistory', () {
    BackupHistory sample({
      String id = 'hist-1',
      BackupStatus status = BackupStatus.running,
    }) {
      return BackupHistory(
        id: id,
        databaseName: 'db',
        databaseType: 'sqlserver',
        backupPath: '/tmp/backup.bak',
        fileSize: 1024,
        status: status,
        startedAt: DateTime(2026),
      );
    }

    test('equality compares by id only', () {
      final a = sample();
      final b = BackupHistory(
        id: 'hist-1',
        databaseName: 'other',
        databaseType: 'postgres',
        backupPath: '/other',
        fileSize: 0,
        status: BackupStatus.error,
        startedAt: DateTime(2020),
      );
      final c = sample(id: 'hist-2');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces fields', () {
      final original = sample();
      final updated = original.copyWith(
        status: BackupStatus.success,
        fileSize: 2048,
      );
      expect(updated.id, 'hist-1');
      expect(updated.status, BackupStatus.success);
      expect(updated.fileSize, 2048);
      expect(updated.databaseName, 'db');
    });

    test('factory assigns id when omitted', () {
      final history = BackupHistory(
        databaseName: 'db',
        databaseType: 'firebird',
        backupPath: '/x',
        fileSize: 1,
        status: BackupStatus.running,
        startedAt: DateTime(2026),
      );
      expect(history.id, isNotEmpty);
      expect(history.backupType, 'full');
    });

    test('backupType defaults to full', () {
      final history = BackupHistory(
        databaseName: 'db',
        databaseType: 'sybase',
        backupPath: '/x',
        fileSize: 1,
        status: BackupStatus.running,
        startedAt: DateTime(2026),
      );
      expect(history.backupType, 'full');
    });
  });
}
