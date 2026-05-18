import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/client/backup_event_deduplicator.dart';
import 'package:flutter_test/flutter_test.dart';

Message _progress({
  String? eventId,
  int? sequence,
  String? runId,
}) {
  return createBackupProgressMessage(
    requestId: 1,
    scheduleId: 'sch-1',
    step: 'Executando',
    message: 'ok',
    runId: runId,
    eventId: eventId,
    sequence: sequence,
  );
}

void main() {
  group('BackupEventDeduplicator', () {
    test('accepts legacy messages without eventId or sequence', () {
      final dedup = BackupEventDeduplicator();
      expect(dedup.shouldAccept(_progress()), isTrue);
      expect(dedup.shouldAccept(_progress()), isTrue);
    });

    test('rejects duplicate eventId', () {
      final dedup = BackupEventDeduplicator();
      final msg = _progress(eventId: 'evt-1', sequence: 1, runId: 'run-1');

      expect(dedup.shouldAccept(msg), isTrue);
      expect(dedup.shouldAccept(msg), isFalse);
    });

    test('rejects stale sequence for same runId', () {
      final dedup = BackupEventDeduplicator();
      expect(
        dedup.shouldAccept(_progress(sequence: 5, runId: 'run-1')),
        isTrue,
      );
      expect(
        dedup.shouldAccept(_progress(sequence: 3, runId: 'run-1')),
        isFalse,
      );
      expect(
        dedup.shouldAccept(_progress(sequence: 6, runId: 'run-1')),
        isTrue,
      );
    });

    test('clear resets state', () {
      final dedup = BackupEventDeduplicator();
      final msg = _progress(eventId: 'evt-1', sequence: 1, runId: 'run-1');
      expect(dedup.shouldAccept(msg), isTrue);
      expect(dedup.shouldAccept(msg), isFalse);

      dedup.clear();
      expect(dedup.shouldAccept(msg), isTrue);
    });

    test('forgetRun allows higher sequence after terminal event', () {
      final dedup = BackupEventDeduplicator();
      expect(
        dedup.shouldAccept(_progress(sequence: 10, runId: 'run-1')),
        isTrue,
      );
      dedup.forgetRun('run-1');
      expect(
        dedup.shouldAccept(_progress(sequence: 1, runId: 'run-1')),
        isTrue,
      );
    });
  });
}
