import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';

/// Dedup de eventos de execucao remota por `eventId` / `sequence` (F2.17).
///
/// Apos reconnect o servidor (ou o cliente ao re-sincronizar) pode
/// reenviar `backupProgress`/`Complete`/`Failed` ja vistos. Ignorar
/// duplicatas evita progresso dobrado na UI e callbacks repetidos.
class BackupEventDeduplicator {
  final Set<String> _seenEventIds = <String>{};
  final Map<String, int> _lastSequenceByRunId = <String, int>{};

  /// `true` quando o evento deve ser processado; `false` se duplicata.
  bool shouldAccept(Message message) {
    return shouldAcceptFields(
      eventId: getEventIdFromBackupMessage(message),
      sequence: getSequenceFromBackupMessage(message),
      runId: getRunIdFromBackupMessage(message),
    );
  }

  bool shouldAcceptFields({
    String? eventId,
    int? sequence,
    String? runId,
  }) {
    final hasEventId = eventId != null && eventId.isNotEmpty;
    if (hasEventId && _seenEventIds.contains(eventId)) {
      return false;
    }

    if (sequence != null && runId != null && runId.isNotEmpty) {
      final last = _lastSequenceByRunId[runId] ?? 0;
      if (sequence <= last) {
        return false;
      }
    }

    if (hasEventId) {
      _seenEventIds.add(eventId);
    }
    if (sequence != null && runId != null && runId.isNotEmpty) {
      _lastSequenceByRunId[runId] = sequence;
    }

    return true;
  }

  void forgetRun(String runId) {
    _lastSequenceByRunId.remove(runId);
  }

  void clear() {
    _seenEventIds.clear();
    _lastSequenceByRunId.clear();
  }
}
