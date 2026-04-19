import 'dart:async';

import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:backup_database/infrastructure/socket/server/queue_event_bus.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';

/// Handler para `startBackup` nao-bloqueante (M2.2/PR-2) e
/// `cancelBackup` (PR-2).
///
/// Diferenca chave em relacao a `ScheduleMessageHandler.executeSchedule`:
/// `startBackup` responde IMEDIATAMENTE com `runId` + `state`, sem
/// aguardar a conclusao real do backup. O backup roda em background
/// (`unawaited`) e os eventos `backupProgress/Complete/Failed` chegam
/// separados via stream — cada um carregando o `runId` para
/// correlacao no cliente.
///
/// `executeSchedule` legacy (bloqueante) continua existindo no
/// `ScheduleMessageHandler` para compat com clientes v1; novos
/// clientes devem usar `startBackup` quando o servidor anunciar
/// suporte via `capabilities.supportsAsyncStart` (futura flag).
class ExecutionMessageHandler {
  ExecutionMessageHandler({
    required IScheduleRepository scheduleRepository,
    required IBackupDestinationRepository destinationRepository,
    required ILicensePolicyService licensePolicyService,
    required ISchedulerService schedulerService,
    required ExecuteScheduledBackup executeBackup,
    required IBackupProgressNotifier progressNotifier,
    required RemoteExecutionRegistry executionRegistry,
    IdempotencyRegistry? idempotencyRegistry,
    ExecutionQueueService? queueService,
    QueueEventBus? eventBus,
    DateTime Function()? clock,
  })  : _scheduleRepository = scheduleRepository,
        _destinationRepository = destinationRepository,
        _licensePolicyService = licensePolicyService,
        _schedulerService = schedulerService,
        _executeBackup = executeBackup,
        _progressNotifier = progressNotifier,
        _executionRegistry = executionRegistry,
        _idempotencyRegistry = idempotencyRegistry ?? IdempotencyRegistry(),
        _queueService = queueService ?? ExecutionQueueService(),
        _eventBus = eventBus,
        _clock = clock ?? DateTime.now;

  final IScheduleRepository _scheduleRepository;
  final IBackupDestinationRepository _destinationRepository;
  final ILicensePolicyService _licensePolicyService;
  final ISchedulerService _schedulerService;
  final ExecuteScheduledBackup _executeBackup;
  final IBackupProgressNotifier _progressNotifier;
  final RemoteExecutionRegistry _executionRegistry;
  final IdempotencyRegistry _idempotencyRegistry;
  final ExecutionQueueService _queueService;
  // PR-3a: bus de eventos de fila. Optional — quando nao cabeado,
  // backup ainda funciona, apenas sem publicar backupQueued/Dequeued/
  // Started (cliente fallback para polling via getExecutionQueue).
  final QueueEventBus? _eventBus;
  final DateTime Function() _clock;

  /// Acesso ao queue service para wirings externos (ex.:
  /// `ExecutionQueueMessageHandler` que reporta a fila ao cliente).
  ExecutionQueueService get queueService => _queueService;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final type = message.header.type;
    if (type != MessageType.startBackupRequest &&
        type != MessageType.cancelBackupRequest &&
        type != MessageType.cancelQueuedBackupRequest) {
      return;
    }

    if (type == MessageType.startBackupRequest) {
      await _handleStart(clientId, message, sendToClient);
    } else if (type == MessageType.cancelBackupRequest) {
      await _handleCancel(clientId, message, sendToClient);
    } else {
      await _handleCancelQueued(clientId, message, sendToClient);
    }
  }

  // ---------------------------------------------------------------------
  // startBackup (nao-bloqueante)
  // ---------------------------------------------------------------------
  Future<void> _handleStart(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final payload = message.payload;
    final scheduleId = payload['scheduleId'] is String
        ? payload['scheduleId'] as String
        : '';
    if (scheduleId.isEmpty) {
      await _sendErrorMsg(
        clientId,
        requestId,
        '`scheduleId` ausente ou vazio',
        ErrorCode.invalidRequest,
        sendToClient,
      );
      return;
    }
    final queueIfBusy = payload['queueIfBusy'] == true;

    final idempotencyKey = getIdempotencyKey(message);

    try {
      final response = await _idempotencyRegistry.runIdempotent<Message>(
        key: idempotencyKey,
        compute: () => _doStart(
          clientId,
          requestId,
          scheduleId,
          sendToClient,
          queueIfBusy: queueIfBusy,
        ),
      );
      await sendToClient(clientId, response);
    } on _StartFailure catch (f) {
      // Falha de validacao -> error message (NAO cacheada pela
      // idempotency registry conforme regra "fail-NO-cache").
      await _sendErrorMsg(
        clientId,
        requestId,
        f.message,
        f.errorCode,
        sendToClient,
      );
    }
  }

  /// Executa toda validacao + reserva runId + dispara backup async +
  /// retorna a `startBackupResponse` que sera entregue ao cliente.
  /// Quando algo falha, lanca [_StartFailure] (capturado pelo caller
  /// para emitir error response — assim o registry de idempotencia
  /// nao cacheia a falha).
  Future<Message> _doStart(
    String clientId,
    int requestId,
    String scheduleId,
    SendToClient sendToClient, {
    required bool queueIfBusy,
  }) async {
    LoggerService.infoWithContext(
      'startBackup requested',
      clientId: clientId,
      requestId: requestId.toString(),
      scheduleId: scheduleId,
    );

    final isBusy = _schedulerService.isExecutingBackup ||
        _executionRegistry.hasActiveForSchedule(scheduleId);

    if (isBusy && !queueIfBusy) {
      // Disparo manual padrao: rejeita com 409.
      throw const _StartFailure(
        'Ja existe um backup em execucao no servidor',
        ErrorCode.backupAlreadyRunning,
      );
    }

    if (isBusy && queueIfBusy) {
      // Cliente aceita ser enfileirado. Verifica se schedule ja esta
      // na fila (defesa contra cliente que retransmite enqueue) e
      // se a fila tem espaco.
      if (_queueService.isScheduleQueued(scheduleId)) {
        throw const _StartFailure(
          'Agendamento ja esta enfileirado',
          ErrorCode.backupAlreadyRunning,
        );
      }
      final item = _queueService.tryEnqueue(
        scheduleId: scheduleId,
        clientId: clientId,
        requestId: requestId,
        requestedBy: clientId,
      );
      if (item == null) {
        // Fila cheia (queueSize >= maxQueueSize) -> 503 retryable.
        // Cliente deve aplicar backoff e tentar de novo apos
        // receber backupComplete/Failed do backup ativo.
        throw const _StartFailure(
          'Fila de execucao esta cheia, tente novamente em breve',
          ErrorCode.unknown,
        );
      }
      LoggerService.infoWithContext(
        'startBackup queued',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
      );
      final queuePosition = _queueService.snapshot()
          .firstWhere((q) => q.runId == item.runId)
          .queuedPosition;
      // Publica `backupQueued` event (fire-and-forget). Cliente
      // pode usar para mostrar "Aguardando na fila (posicao N)" em
      // tempo real, em vez de fazer polling do `getExecutionQueue`.
      unawaited(
        _eventBus?.publishQueued(
              clientId: clientId,
              runId: item.runId,
              scheduleId: scheduleId,
              queuePosition: queuePosition,
              requestedBy: clientId,
            ) ??
            Future<void>.value(),
      );
      return createStartBackupResponse(
        requestId: requestId,
        runId: item.runId,
        state: ExecutionState.queued,
        scheduleId: scheduleId,
        serverTimeUtc: _clock(),
        queuePosition: queuePosition,
        message: 'Backup enfileirado',
      );
    }

    final scheduleResult = await _scheduleRepository.getById(scheduleId);
    final schedule = scheduleResult.getOrNull();
    if (scheduleResult.isError() || schedule == null) {
      throw const _StartFailure(
        'Agendamento nao encontrado',
        ErrorCode.scheduleNotFound,
      );
    }

    // Pre-checagens caras (license, destinations) ANTES de reservar
    // runId/slot — senao um runId fica orfao em caso de license fail.
    final destinationsResult =
        await _destinationRepository.getByIds(schedule.destinationIds);
    if (destinationsResult.isError()) {
      throw const _StartFailure(
        'Falha ao carregar destinos para validacao',
        ErrorCode.unknown,
      );
    }
    final destinations = destinationsResult.getOrNull()!;
    final policyResult = await _licensePolicyService
        .validateExecutionCapabilities(schedule, destinations);
    if (policyResult.isError()) {
      throw const _StartFailure(
        'Licenca nao permite execucao deste agendamento',
        ErrorCode.licenseDenied,
      );
    }

    // Reserva slot global de progresso. Se ja estiver ocupado por
    // outro fluxo (executeSchedule legacy disparado em paralelo),
    // rejeita com 409.
    if (!_progressNotifier.tryStartBackup(schedule.name)) {
      throw const _StartFailure(
        'Slot de progresso ja em uso',
        ErrorCode.backupAlreadyRunning,
      );
    }

    final runId = _executionRegistry.generateRunId(scheduleId);
    _executionRegistry.register(
      runId: runId,
      scheduleId: scheduleId,
      clientId: clientId,
      requestId: requestId,
      sendToClient: sendToClient,
    );

    LogContext.setContext(runId: runId, scheduleId: scheduleId);

    // Dispara o backup em background. O Future NAO e awaited aqui —
    // por isso `startBackup` retorna IMEDIATAMENTE. O backup
    // continua rodando; eventos chegam via progressNotifier->stream.
    unawaited(_runBackupAsync(
      clientId: clientId,
      requestId: requestId,
      scheduleId: scheduleId,
      runId: runId,
      scheduleName: schedule.name,
      sendToClient: sendToClient,
    ));

    return createStartBackupResponse(
      requestId: requestId,
      runId: runId,
      state: ExecutionState.running,
      scheduleId: scheduleId,
      serverTimeUtc: _clock(),
      message: 'Backup iniciado em background',
    );
  }

  /// Executa o backup em background. Captura erros e emite
  /// `backupFailed`/`backupComplete` com `runId`. NUNCA propaga
  /// exception (rodando em fire-and-forget — qualquer erro nao-tratado
  /// viraria uncaught zone error).
  Future<void> _runBackupAsync({
    required String clientId,
    required int requestId,
    required String scheduleId,
    required String runId,
    required String scheduleName,
    required SendToClient sendToClient,
  }) async {
    try {
      _progressNotifier.setCurrentBackupName(scheduleName);
      _progressNotifier.updateProgress(
        step: 'Iniciando',
        message: 'Iniciando backup: $scheduleName',
        progress: 0,
      );

      final result = await _executeBackup(scheduleId);

      if (result.isError()) {
        final failure = result.exceptionOrNull();
        final errorMessage = failure?.toString() ?? 'Falha desconhecida';
        LoggerService.warningWithContext(
          'startBackup async: backup failed',
          clientId: clientId,
          requestId: requestId.toString(),
          scheduleId: scheduleId,
          error: failure,
        );
        await sendToClient(
          clientId,
          createBackupFailedMessage(
            requestId: requestId,
            scheduleId: scheduleId,
            error: errorMessage,
            runId: runId,
          ),
        );
        _progressNotifier.failBackup(errorMessage);
        return;
      }

      LoggerService.infoWithContext(
        'startBackup async: backup completed',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
      );

      // backupComplete e enviado pelo SchedulerService via
      // progressNotifier; aqui apenas garantimos o cleanup do
      // registry. unregister e idempotente.
    } on Object catch (e, st) {
      LoggerService.warningWithContext(
        'startBackup async: unexpected error',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
        error: e,
        stackTrace: st,
      );
      try {
        await sendToClient(
          clientId,
          createBackupFailedMessage(
            requestId: requestId,
            scheduleId: scheduleId,
            error: e.toString(),
            runId: runId,
          ),
        );
        _progressNotifier.failBackup(e.toString());
      } on Object {
        // ignore: client may have disconnected
      }
    } finally {
      _executionRegistry.unregister(runId);
      // Drena proximo da fila (se houver). Sem await — cada drain e
      // independente e roda em zona propria via unawaited.
      unawaited(_drainNextFromQueue());
    }
  }

  /// Tenta iniciar o proximo item da fila. Chamado quando um backup
  /// termina ou quando uma execucao manual e cancelada. Idempotente
  /// (no-op se a fila esta vazia ou se ainda ha backup em curso —
  /// ultima checagem evita race entre dois drains concorrentes).
  Future<void> _drainNextFromQueue() async {
    if (_schedulerService.isExecutingBackup || _executionRegistry.hasAny) {
      return; // ainda ha backup ativo; nao drena
    }
    final next = _queueService.dequeue();
    if (next == null) return;

    LoggerService.infoWithContext(
      'queue drain: starting next backup',
      clientId: next.clientId,
      requestId: next.requestId.toString(),
      scheduleId: next.scheduleId,
    );

    // Publica `backupDequeued(reason=dispatched)` antes de validar
    // schedule — cliente sabe que o item saiu da fila mesmo se a
    // tentativa de iniciar falhar (ex.: schedule deletado).
    unawaited(
      _eventBus?.publishDequeued(
            clientId: next.clientId,
            runId: next.runId,
            scheduleId: next.scheduleId,
            reason: 'dispatched',
          ) ??
          Future<void>.value(),
    );

    // Carrega schedule novamente (pode ter mudado entre enqueue e
    // dequeue: ex.: deletado, desabilitado, modificado). Aborta com
    // log se schedule nao existe mais.
    final scheduleResult = await _scheduleRepository.getById(next.scheduleId);
    final schedule = scheduleResult.getOrNull();
    if (scheduleResult.isError() || schedule == null) {
      LoggerService.warningWithContext(
        'queue drain: schedule no longer exists, dropping queued backup',
        clientId: next.clientId,
        scheduleId: next.scheduleId,
      );
      // Recursivo (sem await — fire-and-forget) para tentar proximo
      unawaited(_drainNextFromQueue());
      return;
    }

    if (!_progressNotifier.tryStartBackup(schedule.name)) {
      // Slot ocupado (race?) — re-enfileira para tentar depois.
      LoggerService.warningWithContext(
        'queue drain: progress slot busy, re-enqueueing',
        scheduleId: next.scheduleId,
      );
      _queueService.tryEnqueue(
        scheduleId: next.scheduleId,
        clientId: next.clientId,
        requestId: next.requestId,
        requestedBy: next.requestedBy,
      );
      return;
    }

    _executionRegistry.register(
      runId: next.runId,
      scheduleId: next.scheduleId,
      clientId: next.clientId,
      requestId: next.requestId,
      sendToClient: (clientId, message) async {
        // Em PR-3 commit final, isso vira lookup pelo
        // ClientManager para garantir entrega mesmo se o cliente
        // desconectou e reconectou. Por agora, tenta o clientId
        // original — se o socket morreu, o ClientHandler.send
        // retorna sem efeito.
        // Wiring real do sendToClient sera injetado pelo
        // tcp_socket_server quando drain rodar — por enquanto
        // o handler ainda usa o sendToClient capturado da request
        // original via _sendToClientResolver.
        await _sendToClientResolver(clientId, message);
      },
    );

    LogContext.setContext(runId: next.runId, scheduleId: next.scheduleId);

    // Publica `backupStarted` antes de iniciar — cliente atualiza
    // UI para "Em execucao" sincronizado com o estado real.
    unawaited(
      _eventBus?.publishStarted(
            clientId: next.clientId,
            runId: next.runId,
            scheduleId: next.scheduleId,
          ) ??
          Future<void>.value(),
    );

    unawaited(_runBackupAsync(
      clientId: next.clientId,
      requestId: next.requestId,
      scheduleId: next.scheduleId,
      runId: next.runId,
      scheduleName: schedule.name,
      sendToClient: _sendToClientResolver,
    ));
  }

  // ---------------------------------------------------------------------
  // cancelQueuedBackup (PR-3a)
  // ---------------------------------------------------------------------
  Future<void> _handleCancelQueued(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final payload = message.payload;
    final runId = payload['runId'] is String
        ? payload['runId'] as String
        : '';
    if (runId.isEmpty) {
      await _sendErrorMsg(
        clientId,
        requestId,
        '`runId` ausente ou vazio',
        ErrorCode.invalidRequest,
        sendToClient,
      );
      return;
    }

    final idempotencyKey = getIdempotencyKey(message);

    try {
      final response = await _idempotencyRegistry.runIdempotent<Message>(
        key: idempotencyKey,
        compute: () => _doCancelQueued(clientId, requestId, runId),
      );
      await sendToClient(clientId, response);
    } on _StartFailure catch (f) {
      await _sendErrorMsg(
        clientId,
        requestId,
        f.message,
        f.errorCode,
        sendToClient,
      );
    }
  }

  Future<Message> _doCancelQueued(
    String clientId,
    int requestId,
    String runId,
  ) async {
    // Busca scheduleId associado (necessario para evento + response).
    String? scheduleId;
    final snap = _queueService.snapshot();
    final found = snap
        .cast<QueuedExecution?>()
        .firstWhere((q) => q?.runId == runId, orElse: () => null);
    if (found != null) scheduleId = found.scheduleId;

    final removed = _queueService.removeByRunId(runId);
    if (!removed) {
      return createCancelQueuedBackupResponse(
        requestId: requestId,
        state: ExecutionState.notFound,
        runId: runId,
        serverTimeUtc: _clock(),
        scheduleId: scheduleId,
        message: 'Nenhuma execucao enfileirada com este runId',
        errorCode: ErrorCode.noActiveExecution,
      );
    }

    LoggerService.infoWithContext(
      'cancelQueuedBackup',
      clientId: clientId,
      requestId: requestId.toString(),
      scheduleId: scheduleId ?? 'unknown',
    );

    // Publica `backupDequeued(reason=cancelled)` para o cliente.
    if (scheduleId != null) {
      unawaited(
        _eventBus?.publishDequeued(
              clientId: clientId,
              runId: runId,
              scheduleId: scheduleId,
              reason: 'cancelled',
            ) ??
            Future<void>.value(),
      );
    }

    return createCancelQueuedBackupResponse(
      requestId: requestId,
      state: ExecutionState.cancelled,
      runId: runId,
      serverTimeUtc: _clock(),
      scheduleId: scheduleId,
      message: 'Execucao cancelada da fila',
    );
  }

  /// Resolver de sendToClient para drains. Em PR-3 final sera injetado
  /// como dependency e fara lookup via ClientManager. Por enquanto e
  /// um stub que roda sem efeito quando ninguem cabeou — drain do
  /// servidor continua funcionando, apenas sem notificar o cliente
  /// original (cliente pode poll via getExecutionStatus).
  SendToClient _sendToClientResolver = _noopSendToClient;

  /// Acesso de leitura para wirings que precisam compor com bus.
  SendToClient get sendToClientResolver => _sendToClientResolver;
  set sendToClientResolver(SendToClient resolver) =>
      _sendToClientResolver = resolver;

  static Future<void> _noopSendToClient(
    String clientId,
    Message message,
  ) async {}

  // ---------------------------------------------------------------------
  // cancelBackup
  // ---------------------------------------------------------------------
  Future<void> _handleCancel(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final requestId = message.header.requestId;
    final payload = message.payload;
    final runIdRaw = payload['runId'] is String
        ? payload['runId'] as String
        : null;
    final scheduleIdRaw = payload['scheduleId'] is String
        ? payload['scheduleId'] as String
        : null;
    final hasRun = runIdRaw != null && runIdRaw.isNotEmpty;
    final hasSch = scheduleIdRaw != null && scheduleIdRaw.isNotEmpty;
    if (hasRun == hasSch) {
      await _sendErrorMsg(
        clientId,
        requestId,
        'Informe APENAS um de `runId` ou `scheduleId`',
        ErrorCode.invalidRequest,
        sendToClient,
      );
      return;
    }

    final idempotencyKey = getIdempotencyKey(message);

    try {
      final response = await _idempotencyRegistry.runIdempotent<Message>(
        key: idempotencyKey,
        compute: () => _doCancel(
          clientId,
          requestId,
          runIdRaw,
          scheduleIdRaw,
          sendToClient,
        ),
      );
      await sendToClient(clientId, response);
    } on _StartFailure catch (f) {
      await _sendErrorMsg(
        clientId,
        requestId,
        f.message,
        f.errorCode,
        sendToClient,
      );
    }
  }

  Future<Message> _doCancel(
    String clientId,
    int requestId,
    String? runIdRaw,
    String? scheduleIdRaw,
    SendToClient sendToClient,
  ) async {
    var scheduleId = scheduleIdRaw;
    final runId = runIdRaw;

    // Resolve scheduleId quando cliente passou apenas runId.
    if (runId != null && scheduleId == null) {
      final ctx = _executionRegistry.getByRunId(runId);
      if (ctx == null) {
        return createCancelBackupResponse(
          requestId: requestId,
          state: ExecutionState.notFound,
          serverTimeUtc: _clock(),
          runId: runId,
          message: 'Nenhuma execucao ativa com este runId',
          errorCode: ErrorCode.noActiveExecution,
        );
      }
      scheduleId = ctx.scheduleId;
    }

    if (scheduleId == null) {
      // Defesa: deveria ter sido pego acima
      throw const _StartFailure(
        'scheduleId nao pode ser resolvido',
        ErrorCode.invalidRequest,
      );
    }

    // Verifica se ha execucao ativa para o schedule
    final ctx = _executionRegistry.getActiveByScheduleId(scheduleId);
    if (ctx == null) {
      return createCancelBackupResponse(
        requestId: requestId,
        state: ExecutionState.notFound,
        serverTimeUtc: _clock(),
        scheduleId: scheduleId,
        message: 'Nenhuma execucao ativa para este agendamento',
        errorCode: ErrorCode.noActiveExecution,
      );
    }

    LoggerService.infoWithContext(
      'cancelBackup requested',
      clientId: clientId,
      requestId: requestId.toString(),
      scheduleId: scheduleId,
    );

    final result = await _schedulerService.cancelExecution(scheduleId);
    if (result.isError()) {
      final err = result.exceptionOrNull();
      LoggerService.warningWithContext(
        'cancelBackup failed',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
        error: err,
      );
      return createCancelBackupResponse(
        requestId: requestId,
        state: ExecutionState.failed,
        serverTimeUtc: _clock(),
        runId: ctx.runId,
        scheduleId: scheduleId,
        message: 'Falha ao cancelar: ${err ?? "desconhecido"}',
        errorCode: ErrorCode.unknown,
      );
    }

    return createCancelBackupResponse(
      requestId: requestId,
      state: ExecutionState.cancelled,
      serverTimeUtc: _clock(),
      runId: ctx.runId,
      scheduleId: scheduleId,
      message: 'Cancelamento sinalizado ao scheduler',
    );
  }

  Future<void> _sendErrorMsg(
    String clientId,
    int requestId,
    String message,
    ErrorCode errorCode,
    SendToClient sendToClient,
  ) async {
    await sendToClient(
      clientId,
      createErrorMessage(
        requestId: requestId,
        errorMessage: message,
        errorCode: errorCode,
      ),
    );
  }
}

/// Excecao interna usada para sair cedo do `compute` do
/// IdempotencyRegistry sinalizando falha NAO-cacheavel — o registry
/// limpa o entry quando o compute joga, e o handler externo emite
/// `error message` (nao a response cacheavel).
class _StartFailure implements Exception {
  const _StartFailure(this.message, this.errorCode);
  final String message;
  final ErrorCode errorCode;

  @override
  String toString() => 'StartFailure(${errorCode.code}): $message';
}
