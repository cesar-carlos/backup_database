import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupExecutionContext', () {
    test('value equality compares all fields', () {
      const a = BackupExecutionContext(
        outputDirectory: '/out',
        scheduleId: 's1',
        cancelTag: 't1',
      );
      const b = BackupExecutionContext(
        outputDirectory: '/out',
        scheduleId: 's1',
        cancelTag: 't1',
      );
      const c = BackupExecutionContext(
        outputDirectory: '/out',
        scheduleId: 's1',
        cancelTag: 't2',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces fields', () {
      const original = BackupExecutionContext(
        outputDirectory: '/out',
        scheduleId: 's1',
      );
      final updated = original.copyWith(backupType: BackupType.differential);
      expect(updated.backupType, BackupType.differential);
      expect(updated.outputDirectory, '/out');
      expect(updated.scheduleId, 's1');
    });
  });
}
