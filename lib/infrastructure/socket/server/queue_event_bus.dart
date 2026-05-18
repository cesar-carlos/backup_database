import 'dart:async';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/socket/server/execution_event_sequencer.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';

/// Bus de publicacao de eventos de fila (PR-3a).
///
/// Centraliza:
/// - **Numeracao monotonica de `sequence`** (atomica in-memory).
/// - **Geracao de `eventId`** (UUID v4 unico por evento).
/// - **Broadcast para clientes interessados** via callback injetavel.
///
/// Cliente recebe os eventos via stream do socket e usa
/// `(eventId, sequence)` para deduplicar e reordenar — defesa contra
/// reconnect que pode receber eventos repetidos.
class QueueEventBus {
  QueueEventBus({
    required Future<void> Function(String clientId, Message message) broadcast,
    ExecutionEventSequencer? sequencer,
    DateTime Function()? clock,
  }) : _broadcast = broadcast,
       _sequencer = sequencer ?? ExecutionEventSequencer(),
       _clock = clock ?? DateTime.now;

  final Future<void> Function(String clientId, Message) _broadcast;
  final ExecutionEventSequencer _sequencer;
  final DateTime Function() _clock;

  ExecutionEventSequencer get sequencer => _sequencer;

  /// `sequence` atual. Util para testes/observabilidade.
  int get currentSequence => _sequencer.currentSequence;

  /// Publica `backupQueued` para o cliente que disparou.
  Future<void> publishQueued({
    required String clientId,
    required String runId,
    required String scheduleId,
    int? queuePosition,
    String? requestedBy,
    String? message,
  }) async {
    final meta = _sequencer.next();
    final event = createBackupQueuedEvent(
      runId: runId,
      scheduleId: scheduleId,
      sequence: meta.sequence,
      eventId: meta.eventId,
      serverTimeUtc: _clock(),
      queuePosition: queuePosition,
      requestedBy: requestedBy,
      message: message,
    );
    await _safeBroadcast(clientId, event);
  }

  /// Publica `backupDequeued` para o cliente.
  Future<void> publishDequeued({
    required String clientId,
    required String runId,
    required String scheduleId,
    String? reason,
    String? message,
  }) async {
    final meta = _sequencer.next();
    final event = createBackupDequeuedEvent(
      runId: runId,
      scheduleId: scheduleId,
      sequence: meta.sequence,
      eventId: meta.eventId,
      serverTimeUtc: _clock(),
      reason: reason,
      message: message,
    );
    await _safeBroadcast(clientId, event);
  }

  /// Publica `backupStarted` para o cliente.
  Future<void> publishStarted({
    required String clientId,
    required String runId,
    required String scheduleId,
    String? message,
  }) async {
    final meta = _sequencer.next();
    final event = createBackupStartedEvent(
      runId: runId,
      scheduleId: scheduleId,
      sequence: meta.sequence,
      eventId: meta.eventId,
      serverTimeUtc: _clock(),
      message: message,
    );
    await _safeBroadcast(clientId, event);
  }

  Future<void> _safeBroadcast(String clientId, Message event) async {
    try {
      await _broadcast(clientId, event);
    } on Object catch (e, st) {
      // Cliente desconectou ou outro erro — eventos nao devem
      // derrubar o fluxo de execucao do backup. Apenas log.
      LoggerService.warning(
        'QueueEventBus: broadcast falhou para $clientId: $e',
        e,
        st,
      );
    }
  }
}

/// Wiring helper: cria um broadcast que despacha pelo
/// [SendToClient] cabeado no servidor.
Future<void> Function(String clientId, Message message)
queueEventBroadcastFromSendToClient(SendToClient send) {
  return send;
}
