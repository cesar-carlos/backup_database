import 'package:backup_database/infrastructure/socket/server/queue_event_bus.dart' show QueueEventBus;
import 'package:uuid/uuid.dart';

/// Metadados de correlacao para eventos de execucao remota (F2.17).
typedef ExecutionEventMetadata = ({String eventId, int sequence});

/// Numeracao monotonica de `sequence` + `eventId` por servidor.
///
/// Compartilhado entre [QueueEventBus] e mensagens
/// `backupProgress`/`Complete`/`Failed` para que o cliente ordene e
/// deduplique todos os eventos de uma sessao com um unico contador.
class ExecutionEventSequencer {
  ExecutionEventSequencer({
    Uuid? uuid,
    int initialSequence = 0,
  }) : _uuid = uuid ?? const Uuid(),
       _sequence = initialSequence;

  final Uuid _uuid;
  int _sequence;

  int get currentSequence => _sequence;

  ExecutionEventMetadata next() {
    return (eventId: _uuid.v4(), sequence: ++_sequence);
  }
}
