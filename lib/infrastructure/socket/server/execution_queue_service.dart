import 'dart:collection';

import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:uuid/uuid.dart';

/// Item enfileirado no [ExecutionQueueService]. Mantem callbacks de
/// envio para que, quando dequeueado, o backup continue podendo
/// notificar o cliente original (mesmo apos clientes terem entrado/
/// saido entre o enqueue e o dequeue).
class QueuedExecutionItem {
  QueuedExecutionItem({
    required this.runId,
    required this.scheduleId,
    required this.clientId,
    required this.requestId,
    required this.requestedBy,
    required this.queuedAt,
  });

  final String runId;
  final String scheduleId;
  final String clientId;
  final int requestId;
  final String requestedBy; // identificador legivel (ex.: clientId hash)
  final DateTime queuedAt;
}

/// Servico de fila FIFO para execucoes remotas (PR-3a).
///
/// Garante:
/// - **maxConcurrentBackups = 1** via [hasActive] (consultado pelo
///   handler de start). Quando `hasActive`, novos starts vao para
///   fila em vez de rejeitar (com `queueIfBusy=true`) ou rejeitar
///   com 409 (com `queueIfBusy=false` — disparo manual padrao).
/// - **FIFO**: ordem de chegada e respeitada no dequeue.
/// - **Limite [maxQueueSize]**: rejeita enqueue alem do limite com
///   resposta `queue full` (cliente decide retry/abort).
/// - **Deduplicacao por `scheduleId`**: nao enfileira mesmo schedule
///   duas vezes simultaneamente — defesa contra cliente buggy ou
///   scheduler local agendando varios disparos do mesmo schedule.
/// - **runId estavel**: cada item recebe runId proprio assim que
///   enfileirado, persistido em [QueuedExecutionItem.runId]. Cliente
///   pode consultar status/cancel pelo runId mesmo enquanto na fila.
///
/// Persistencia entra em PR-3 commit 5 (in-memory por enquanto).
class ExecutionQueueService {
  ExecutionQueueService({
    int maxQueueSize = 50,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _maxQueueSize = maxQueueSize,
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final int _maxQueueSize;
  final Uuid _uuid;
  final DateTime Function() _clock;

  final Queue<QueuedExecutionItem> _queue = Queue<QueuedExecutionItem>();
  final Set<String> _scheduleIdsInQueue = <String>{};

  /// Indica se ha backup em execucao agora. Setado externamente pelo
  /// handler que reserva o slot global via `progressNotifier.tryStartBackup`.
  /// Mantido aqui apenas para visibilidade — _service NAO controla
  /// o slot de execucao real (apenas a fila pendente).
  bool _hasActive = false;
  bool get hasActive => _hasActive;
  // ignore: avoid_setters_without_getters — semantica e clara.
  set hasActive(bool value) => _hasActive = value;

  /// Tamanho atual da fila.
  int get queueSize => _queue.length;
  int get maxQueueSize => _maxQueueSize;
  bool get isFull => _queue.length >= _maxQueueSize;
  bool get isEmpty => _queue.isEmpty;

  /// Ja existe item enfileirado para o `scheduleId`?
  bool isScheduleQueued(String scheduleId) =>
      _scheduleIdsInQueue.contains(scheduleId);

  /// Snapshot ordenado da fila (FIFO). Usado por
  /// `ExecutionQueueMessageHandler` para responder `getExecutionQueue`.
  List<QueuedExecution> snapshot() {
    return _queue.toList(growable: false).asMap().entries.map((entry) {
      final i = entry.key;
      final it = entry.value;
      return QueuedExecution(
        runId: it.runId,
        scheduleId: it.scheduleId,
        queuedAt: it.queuedAt,
        queuedPosition: i + 1, // 1-based para cliente
        requestedBy: it.requestedBy,
      );
    }).toList(growable: false);
  }

  /// Tenta enfileirar uma execucao. Retorna o item criado (com
  /// `runId` ja gerado) ou `null` quando a fila esta cheia ou o
  /// `scheduleId` ja esta enfileirado.
  ///
  /// O `runId` segue o formato `<scheduleId>_<uuid>` para correlacao
  /// com `RemoteExecutionRegistry` (mesma convencao).
  QueuedExecutionItem? tryEnqueue({
    required String scheduleId,
    required String clientId,
    required int requestId,
    required String requestedBy,
  }) {
    if (isFull) return null;
    if (isScheduleQueued(scheduleId)) return null;

    final runId = '${scheduleId}_${_uuid.v4()}';
    final item = QueuedExecutionItem(
      runId: runId,
      scheduleId: scheduleId,
      clientId: clientId,
      requestId: requestId,
      requestedBy: requestedBy,
      queuedAt: _clock(),
    );
    _queue.addLast(item);
    _scheduleIdsInQueue.add(scheduleId);
    return item;
  }

  /// Remove e retorna o proximo item da fila (FIFO). `null` se vazia.
  QueuedExecutionItem? dequeue() {
    if (_queue.isEmpty) return null;
    final it = _queue.removeFirst();
    _scheduleIdsInQueue.remove(it.scheduleId);
    return it;
  }

  /// Remove um item da fila por `runId`. Usado pelo
  /// `cancelQueuedBackup`. Retorna `true` se removido, `false` se
  /// nao encontrado.
  bool removeByRunId(String runId) {
    final beforeLen = _queue.length;
    _queue.removeWhere((it) {
      if (it.runId == runId) {
        _scheduleIdsInQueue.remove(it.scheduleId);
        return true;
      }
      return false;
    });
    return _queue.length < beforeLen;
  }

  /// Remove todos os itens (shutdown / testes).
  void clear() {
    _queue.clear();
    _scheduleIdsInQueue.clear();
  }
}
