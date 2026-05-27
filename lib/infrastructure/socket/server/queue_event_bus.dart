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

/// Extensão fire-and-forget sobre `QueueEventBus?`. Centraliza o
/// pattern `unawaited(eventBus?.publishX(...) ?? Future<void>.value())`
/// que aparecia em ~5 pontos do `ExecutionMessageHandler`.
///
/// Uso:
/// ```dart
/// eventBus.fireAndForgetQueued(clientId: ..., runId: ..., scheduleId: ...);
/// ```
///
/// Quando o bus é `null` (DI ainda não cabeou ou modo de teste sem
/// broadcast), o helper é no-op. Quando existe, o publish é disparado
/// sem `await` e qualquer erro é capturado pelo `_safeBroadcast`
/// interno (que já loga warning).
extension QueueEventBusFireAndForget on QueueEventBus? {
  void fireAndForgetQueued({
    required String clientId,
    required String runId,
    required String scheduleId,
    int? queuePosition,
    String? requestedBy,
    String? message,
  }) {
    final bus = this;
    if (bus == null) return;
    unawaited(
      bus.publishQueued(
        clientId: clientId,
        runId: runId,
        scheduleId: scheduleId,
        queuePosition: queuePosition,
        requestedBy: requestedBy,
        message: message,
      ),
    );
  }

  void fireAndForgetDequeued({
    required String clientId,
    required String runId,
    required String scheduleId,
    String? reason,
    String? message,
  }) {
    final bus = this;
    if (bus == null) return;
    unawaited(
      bus.publishDequeued(
        clientId: clientId,
        runId: runId,
        scheduleId: scheduleId,
        reason: reason,
        message: message,
      ),
    );
  }

  void fireAndForgetStarted({
    required String clientId,
    required String runId,
    required String scheduleId,
    String? message,
  }) {
    final bus = this;
    if (bus == null) return;
    unawaited(
      bus.publishStarted(
        clientId: clientId,
        runId: runId,
        scheduleId: scheduleId,
        message: message,
      ),
    );
  }
}

/// Wiring helper: cria um broadcast que despacha pelo
/// [SendToClient] cabeado no servidor.
Future<void> Function(String clientId, Message message)
queueEventBroadcastFromSendToClient(SendToClient send) {
  return send;
}
