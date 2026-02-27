import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/value_objects/backup_history_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupHistoryStateMachine', () {
    group('isTerminal', () {
      test('returns true for success, error, warning', () {
        expect(BackupHistoryStateMachine.isTerminal(BackupStatus.success), true);
        expect(BackupHistoryStateMachine.isTerminal(BackupStatus.error), true);
        expect(BackupHistoryStateMachine.isTerminal(BackupStatus.warning), true);
      });

      test('returns false for running', () {
        expect(BackupHistoryStateMachine.isTerminal(BackupStatus.running), false);
      });
    });

    group('canTransition', () {
      test('allows running -> success', () {
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.running,
            BackupStatus.success,
          ),
          true,
        );
      });

      test('allows running -> error', () {
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.running,
            BackupStatus.error,
          ),
          true,
        );
      });

      test('allows running -> warning', () {
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.running,
            BackupStatus.warning,
          ),
          true,
        );
      });

      test('allows same-state transition (no-op)', () {
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.running,
            BackupStatus.running,
          ),
          true,
        );
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.success,
            BackupStatus.success,
          ),
          true,
        );
      });

      test('rejects success -> any other', () {
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.success,
            BackupStatus.error,
          ),
          false,
        );
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.success,
            BackupStatus.warning,
          ),
          false,
        );
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.success,
            BackupStatus.running,
          ),
          false,
        );
      });

      test('rejects error -> any other', () {
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.error,
            BackupStatus.success,
          ),
          false,
        );
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.error,
            BackupStatus.running,
          ),
          false,
        );
      });

      test('rejects warning -> any other', () {
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.warning,
            BackupStatus.success,
          ),
          false,
        );
        expect(
          BackupHistoryStateMachine.canTransition(
            BackupStatus.warning,
            BackupStatus.running,
          ),
          false,
        );
      });
    });

    group('canTransitionFrom', () {
      test('returns true only for running', () {
        expect(
          BackupHistoryStateMachine.canTransitionFrom(BackupStatus.running),
          true,
        );
      });

      test('returns false for terminal states', () {
        expect(
          BackupHistoryStateMachine.canTransitionFrom(BackupStatus.success),
          false,
        );
        expect(
          BackupHistoryStateMachine.canTransitionFrom(BackupStatus.error),
          false,
        );
        expect(
          BackupHistoryStateMachine.canTransitionFrom(BackupStatus.warning),
          false,
        );
      });
    });
  });
}
