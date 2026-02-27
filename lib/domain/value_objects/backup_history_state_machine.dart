import 'package:backup_database/domain/entities/backup_history.dart';

/// Formal state machine for [BackupHistory] status transitions.
///
/// Valid transitions:
/// - [BackupStatus.running] → [BackupStatus.success]
/// - [BackupStatus.running] → [BackupStatus.error]
/// - [BackupStatus.running] → [BackupStatus.warning]
///
/// Terminal states (no outgoing transitions):
/// - [BackupStatus.success]
/// - [BackupStatus.error]
/// - [BackupStatus.warning]
///
/// Invalid: any transition from a terminal state, or to [BackupStatus.running].
class BackupHistoryStateMachine {
  BackupHistoryStateMachine._();

  static const List<BackupStatus> _terminalStates = [
    BackupStatus.success,
    BackupStatus.error,
    BackupStatus.warning,
  ];

  static const List<BackupStatus> _validTargetsFromRunning = [
    BackupStatus.success,
    BackupStatus.error,
    BackupStatus.warning,
  ];

  static bool isTerminal(BackupStatus status) =>
      _terminalStates.contains(status);

  static bool canTransition(BackupStatus from, BackupStatus to) {
    if (from == to) return true;
    if (isTerminal(from)) return false;
    if (from != BackupStatus.running) return false;
    return _validTargetsFromRunning.contains(to);
  }

  static bool canTransitionFrom(BackupStatus from) => !isTerminal(from);
}
