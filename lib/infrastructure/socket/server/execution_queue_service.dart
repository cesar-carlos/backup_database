import 'dart:collection';

import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_persistence.dart';
import 'package:backup_database/infrastructure/socket/server/queued_execution_item.dart';
import 'package:uuid/uuid.dart';

export 'queued_execution_item.dart';

/// Servico de fila FIFO para execucoes remotas (PR-3a / F2.16).
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
///   enfileirado. Cliente pode consultar status/cancel pelo runId
///   mesmo enquanto na fila.
///
/// Com persistencia configurada, chame `initialize` antes do primeiro
/// uso (ex.: no bootstrap do socket server) para reidratar a fila
/// apos reinicio do processo.
class ExecutionQueueService {
  ExecutionQueueService({
    int maxQueueSize = 50,
    Uuid? uuid,
    DateTime Function()? clock,
    ExecutionQueuePersistence? persistence,
  })  : _maxQueueSize = maxQueueSize,
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now,
        _persistence = persistence;

  final int _maxQueueSize;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final ExecutionQueuePersistence? _persistence;

  bool _initialized = false;

  final Queue<QueuedExecutionItem> _queue = Queue<QueuedExecutionItem>();
  final Set<String> _scheduleIdsInQueue = <String>{};

  /// Reidrata a fila a partir do armazenamento (no-op se sem
  /// persistencia ou ja inicializado).
  Future<void> initialize() async {
    final persistence = _persistence;
    if (persistence == null || _initialized) return;
    await persistence.trimToMaxSize(_maxQueueSize);
    final items = await persistence.loadOrderedFifo();
    _queue.clear();
    _scheduleIdsInQueue.clear();
    for (final item in items) {
      _queue.addLast(item);
      _scheduleIdsInQueue.add(item.scheduleId);
    }
    _initialized = true;
  }

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
  Future<QueuedExecutionItem?> tryEnqueue({
    required String scheduleId,
    required String clientId,
    required int requestId,
    required String requestedBy,
  }) async {
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

    final persistence = _persistence;
    if (persistence != null) {
      final ok = await persistence.tryInsert(
        item: item,
        maxQueueSize: _maxQueueSize,
      );
      if (!ok) return null;
    }

    _queue.addLast(item);
    _scheduleIdsInQueue.add(scheduleId);
    return item;
  }

  /// Remove e retorna o proximo item da fila (FIFO). `null` se vazia.
  Future<QueuedExecutionItem?> dequeue() async {
    while (true) {
      if (_queue.isEmpty) return null;
      final head = _queue.first;

      final persistence = _persistence;
      if (persistence != null) {
        final deleted = await persistence.deleteByRunId(head.runId);
        if (deleted == 0) {
          await _reloadFromPersistence();
          continue;
        }
      }

      _queue.removeFirst();
      _scheduleIdsInQueue.remove(head.scheduleId);
      return head;
    }
  }

  /// Remove um item da fila por `runId`. Usado pelo
  /// `cancelQueuedBackup`. Retorna `true` se removido, `false` se
  /// nao encontrado.
  Future<bool> removeByRunId(String runId) async {
    final exists = _queue.any((it) => it.runId == runId);
    if (!exists) return false;

    final persistence = _persistence;
    if (persistence != null) {
      await persistence.deleteByRunId(runId);
    }

    _queue.removeWhere((it) {
      if (it.runId == runId) {
        _scheduleIdsInQueue.remove(it.scheduleId);
        return true;
      }
      return false;
    });
    return true;
  }

  /// Remove todos os itens (shutdown / testes).
  Future<void> clear() async {
    final persistence = _persistence;
    if (persistence != null) {
      await persistence.deleteAll();
    }
    _queue.clear();
    _scheduleIdsInQueue.clear();
  }

  Future<void> _reloadFromPersistence() async {
    final persistence = _persistence;
    if (persistence == null) return;
    final items = await persistence.loadOrderedFifo();
    _queue.clear();
    _scheduleIdsInQueue.clear();
    for (final item in items) {
      _queue.addLast(item);
      _scheduleIdsInQueue.add(item.scheduleId);
    }
  }
}
