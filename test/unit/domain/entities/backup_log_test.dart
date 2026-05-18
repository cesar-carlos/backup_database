import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupLog', () {
    test('equality compares by id only', () {
      final a = BackupLog(
        id: 'log-1',
        level: LogLevel.info,
        category: LogCategory.execution,
        message: 'first',
        createdAt: DateTime(2026),
      );
      final b = BackupLog(
        id: 'log-1',
        level: LogLevel.error,
        category: LogCategory.system,
        message: 'second',
        createdAt: DateTime(2026, 6),
      );
      final c = BackupLog(
        id: 'log-2',
        level: LogLevel.info,
        category: LogCategory.execution,
        message: 'first',
        createdAt: DateTime(2026),
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces fields', () {
      final original = BackupLog(
        id: 'log-1',
        level: LogLevel.info,
        category: LogCategory.execution,
        message: 'msg',
      );
      final updated = original.copyWith(level: LogLevel.warning);
      expect(updated.id, 'log-1');
      expect(updated.level, LogLevel.warning);
      expect(updated.message, 'msg');
    });

    test('factory assigns id and createdAt when omitted', () {
      final log = BackupLog(
        level: LogLevel.debug,
        category: LogCategory.audit,
        message: 'auto',
      );
      expect(log.id, isNotEmpty);
      expect(log.createdAt, isNotNull);
    });
  });
}
