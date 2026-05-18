import 'package:backup_database/infrastructure/socket/server/execution_event_sequencer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('ExecutionEventSequencer', () {
    test('next increments sequence and returns UUID eventId', () {
      final sequencer = ExecutionEventSequencer();

      final first = sequencer.next();
      final second = sequencer.next();

      expect(first.sequence, 1);
      expect(second.sequence, 2);
      expect(Uuid.isValidUUID(fromString: first.eventId), isTrue);
      expect(Uuid.isValidUUID(fromString: second.eventId), isTrue);
      expect(first.eventId, isNot(equals(second.eventId)));
    });
  });
}
