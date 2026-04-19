import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';

/// Handles remote schedule commands from the client. When the client sends
/// executeSchedule, the server runs the same backup flow as a local "Run now"
/// (ExecuteScheduledBackup → SchedulerService.executeNow → _executeScheduledBackup).
/// Progress (step, message, progress) is streamed to the client via
/// IBackupProgressNotifier so the client has the same information as the server UI.
class ScheduleMessageHandler {
  ScheduleMessageHandler({
    required IScheduleRepository scheduleRepository,
    required IBackupDestinationRepository destinationRepository,
    required ILicensePolicyService licensePolicyService,
    required ISchedulerService schedulerService,
    required UpdateSchedule updateSchedule,
    required ExecuteScheduledBackup executeBackup,
    required IBackupProgressNotifier progressNotifier,
    RemoteExecutionRegistry? executionRegistry,
  }) : _scheduleRepository = scheduleRepository,
       _destinationRepository = destinationRepository,
       _licensePolicyService = licensePolicyService,
       _schedulerService = schedulerService,
       _updateSchedule = updateSchedule,
       _executeBackup = executeBackup,
       _progressNotifier = progressNotifier,
       _executionRegistry = executionRegistry ?? RemoteExecutionRegistry() {
    _progressNotifier.addListener(_onProgressChanged);
  }

  final IScheduleRepository _scheduleRepository;
  final IBackupDestinationRepository _destinationRepository;
  final ILicensePolicyService _licensePolicyService;
  final ISchedulerService _schedulerService;
  final UpdateSchedule _updateSchedule;
  final ExecuteScheduledBackup _executeBackup;
  final IBackupProgressNotifier _progressNotifier;

  /// Substitui os campos singleton anteriores (`_currentClientId`,
  /// `_currentRequestId`, `_currentScheduleId`, `_sendToClient`). Cada
  /// execucao remota agora vive como um `RemoteExecutionContext` proprio,
  /// indexado por `runId`. Hoje so existe 1 ativo por vez (mutex global
  /// no scheduler), mas a estrutura suporta a fila planejada para PR-3b
  /// sem reescrita do handler.
  final RemoteExecutionRegistry _executionRegistry;

  void dispose() {
    _progressNotifier.removeListener(_onProgressChanged);
    _executionRegistry.clear();
  }

  /// Itera o registry em vez de usar campos singleton. Hoje sempre
  /// processa 0 ou 1 contexto (mutex de 1 backup por vez), mas a
  /// iteracao garante correcao caso a fila futura permita mais de uma
  /// execucao ativa simultaneamente (ex.: priorizacao de manual sobre
  /// agendado, ou pool de workers).
  Future<void> _onProgressChanged() async {
    if (!_executionRegistry.hasAny) return;

    final snapshot = _progressNotifier.currentSnapshot;
    if (snapshot == null) return;

    final progressValue = snapshot.progress ?? 0.0;

    // Snapshot defensivo da lista — se um contexto for desregistrado
    // durante o envio (ex.: dispose concorrente), nao quebra a iteracao.
    final contexts = _executionRegistry.all.toList(growable: false);

    for (final context in contexts) {
      await context.sendToClient(
        context.clientId,
        createBackupProgressMessage(
          requestId: context.requestId,
          scheduleId: context.scheduleId,
          step: snapshot.step,
          message: snapshot.message,
          progress: progressValue,
          runId: context.runId,
        ),
      );

      if (snapshot.step == 'Concluído') {
        LoggerService.debug(
          '[ScheduleMessageHandler] backupComplete runId=${context.runId} '
          'backupPath=${snapshot.backupPath == null || snapshot.backupPath!.isEmpty ? "(empty)" : "(set)"}',
        );

        await context.sendToClient(
          context.clientId,
          createBackupCompleteMessage(
            requestId: context.requestId,
            scheduleId: context.scheduleId,
            message: snapshot.message,
            backupPath: snapshot.backupPath,
            runId: context.runId,
          ),
        );
        _executionRegistry.unregister(context.runId);
      } else if (snapshot.step == 'Erro') {
        await context.sendToClient(
          context.clientId,
          createBackupFailedMessage(
            requestId: context.requestId,
            scheduleId: context.scheduleId,
            error: snapshot.error ?? 'Erro desconhecido',
            runId: context.runId,
          ),
        );
        _executionRegistry.unregister(context.runId);
      }
    }
  }

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isListSchedulesMessage(message) &&
        !isUpdateScheduleMessage(message) &&
        !isExecuteScheduleMessage(message) &&
        !isCancelScheduleMessage(message)) {
      return;
    }

    final requestId = message.header.requestId;

    try {
      if (isListSchedulesMessage(message)) {
        await _handleListSchedules(clientId, requestId, sendToClient);
      } else if (isUpdateScheduleMessage(message)) {
        await _handleUpdateSchedule(
          clientId,
          requestId,
          message,
          sendToClient,
        );
      } else if (isExecuteScheduleMessage(message)) {
        await _handleExecuteSchedule(
          clientId,
          requestId,
          message,
          sendToClient,
        );
      } else if (isCancelScheduleMessage(message)) {
        await _handleCancelSchedule(
          clientId,
          requestId,
          message,
          sendToClient,
        );
      }
    } on Object catch (e, st) {
      LoggerService.warningWithContext(
        'ScheduleMessageHandler error',
        clientId: clientId,
        requestId: requestId.toString(),
        error: e,
        stackTrace: st,
      );
      await sendToClient(
        clientId,
        createScheduleErrorMessage(requestId: requestId, error: e.toString()),
      );
    }
  }

  Future<void> _handleListSchedules(
    String clientId,
    int requestId,
    SendToClient sendToClient,
  ) async {
    final result = await _scheduleRepository.getAll();
    // Bug histórico: este `result.fold(asyncCb, asyncCb)` não aguardava
    // os callbacks — a mensagem podia ainda estar viajando quando o
    // handler retornava, e exceptions do `sendToClient` ficavam invisíveis.
    final schedules = result.getOrNull();
    if (schedules != null) {
      await sendToClient(
        clientId,
        createScheduleListMessage(
          requestId: requestId,
          schedules: schedules,
        ),
      );
      return;
    }
    await _sendError(
      clientId,
      requestId,
      _failureMessage(result.exceptionOrNull()),
      sendToClient,
    );
  }

  Future<void> _handleUpdateSchedule(
    String clientId,
    int requestId,
    Message message,
    SendToClient sendToClient,
  ) async {
    try {
      final schedule = getScheduleFromUpdatePayload(message);
      final result = await _updateSchedule(schedule);
      // Antes: `result.fold((upd) async {...}, (f) async {...})` sem await
      // — bug que poderia perder erros de envio. Agora extrai e usa await.
      final updated = result.getOrNull();
      if (updated != null) {
        await sendToClient(
          clientId,
          createScheduleUpdatedMessage(
            requestId: requestId,
            schedule: updated,
          ),
        );
        return;
      }
      await _sendError(
        clientId,
        requestId,
        _failureMessage(result.exceptionOrNull()),
        sendToClient,
      );
    } on Object catch (e) {
      await _sendError(clientId, requestId, e.toString(), sendToClient);
    }
  }

  Future<void> _handleExecuteSchedule(
    String clientId,
    int requestId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final scheduleId = getScheduleIdFromExecutePayload(message);
    if (scheduleId.isEmpty) {
      await _sendError(clientId, requestId, 'scheduleId vazio', sendToClient);
      return;
    }

    if (_schedulerService.isExecutingBackup) {
      LoggerService.infoWithContext(
        'Execute schedule rejected: scheduler backup in progress',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
      );
      await _sendError(
        clientId,
        requestId,
        'Já existe um backup em execução no servidor. '
        'Aguarde conclusão para iniciar novo.',
        sendToClient,
      );
      return;
    }

    // Defesa em profundidade: se o registry ja tem execucao ativa para
    // este scheduleId, rejeita antes de chamar `tryStartBackup` (evita
    // janela TOCTOU entre `isExecutingBackup` e o registro efetivo).
    if (_executionRegistry.hasActiveForSchedule(scheduleId)) {
      LoggerService.infoWithContext(
        'Execute schedule rejected: schedule already active in registry',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
      );
      await _sendError(
        clientId,
        requestId,
        'Já existe um backup em execução para este agendamento.',
        sendToClient,
      );
      return;
    }

    LoggerService.infoWithContext(
      'Execute schedule started',
      clientId: clientId,
      requestId: requestId.toString(),
      scheduleId: scheduleId,
    );

    var progressSlotReserved = false;
    RemoteExecutionContext? executionContext;
    try {
      final scheduleResult = await _scheduleRepository.getById(scheduleId);
      if (scheduleResult.isError()) {
        await _sendError(
          clientId,
          requestId,
          _failureMessage(
            scheduleResult.exceptionOrNull(),
            fallback: 'Agendamento não encontrado',
          ),
          sendToClient,
        );
        return;
      }

      final schedule = scheduleResult.getOrNull();
      if (schedule == null) {
        await _sendError(
          clientId,
          requestId,
          'Agendamento não encontrado',
          sendToClient,
        );
        return;
      }

      final destinationsResult = await _destinationRepository.getByIds(
        schedule.destinationIds,
      );
      if (destinationsResult.isError()) {
        await _sendError(
          clientId,
          requestId,
          'Não foi possível carregar destinos para validação',
          sendToClient,
        );
        return;
      }
      final destinations = destinationsResult.getOrNull()!;
      final policyResult = await _licensePolicyService
          .validateExecutionCapabilities(
            schedule,
            destinations,
          );
      if (policyResult.isError()) {
        await _sendError(
          clientId,
          requestId,
          _failureMessage(
            policyResult.exceptionOrNull(),
            fallback: 'Licença não permite execução',
          ),
          sendToClient,
        );
        return;
      }

      if (!_progressNotifier.tryStartBackup(schedule.name)) {
        LoggerService.infoWithContext(
          'Execute schedule rejected: progress slot busy',
          clientId: clientId,
          requestId: requestId.toString(),
          scheduleId: scheduleId,
        );
        await _sendError(
          clientId,
          requestId,
          'Já existe um backup em execução no servidor. '
          'Aguarde conclusão para iniciar novo.',
          sendToClient,
        );
        return;
      }
      progressSlotReserved = true;

      // Registra o contexto antes de iniciar o backup para que eventos
      // de progresso encontrem o destinatario correto. O `runId` aqui
      // pertence ao escopo do handler remoto; o `SchedulerService` gera
      // outro internamente para uso em logs/historico — ambos podem
      // coexistir ate PR-2 unificar a geracao no contrato remoto.
      final runId = _executionRegistry.generateRunId(scheduleId);
      executionContext = _executionRegistry.register(
        runId: runId,
        scheduleId: scheduleId,
        clientId: clientId,
        requestId: requestId,
        sendToClient: sendToClient,
      );

      LogContext.setContext(runId: runId, scheduleId: scheduleId);

      _progressNotifier.setCurrentBackupName(schedule.name);
      _progressNotifier.updateProgress(
        step: 'Iniciando',
        message: 'Iniciando backup: ${schedule.name}',
        progress: 0,
      );
      _progressNotifier.updateProgress(
        step: 'Executando backup',
        message: 'Executando backup do banco de dados...',
        progress: 0.2,
      );

      final result = await _executeBackup(scheduleId);

      // Antes: `await result.fold(asyncSuccess, asyncFailure)` com fold
      // aninhado dentro do success. O fold externo tinha `await`, mas o
      // fold aninhado em `updatedScheduleResult.fold(asyncCb, asyncCb)`
      // NÃO — bug clássico: o `sendToClient` async ficava pendurado e
      // qualquer falha de envio era invisível.
      if (result.isError()) {
        final failure = result.exceptionOrNull();
        final errorMessage = _failureMessage(failure);
        LoggerService.warningWithContext(
          'Backup failed',
          clientId: clientId,
          requestId: requestId.toString(),
          scheduleId: scheduleId,
          error: failure,
        );
        await _sendError(clientId, requestId, errorMessage, sendToClient);
        _progressNotifier.failBackup(errorMessage);
        _executionRegistry.unregister(runId);
        return;
      }

      LoggerService.infoWithContext(
        'Backup completed successfully',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
      );
      final updatedScheduleResult =
          await _scheduleRepository.getById(scheduleId);
      final updatedSchedule = updatedScheduleResult.getOrNull();
      if (updatedSchedule != null) {
        await sendToClient(
          clientId,
          createScheduleUpdatedMessage(
            requestId: requestId,
            schedule: updatedSchedule,
          ),
        );
      } else {
        await _sendError(
          clientId,
          requestId,
          _failureMessage(updatedScheduleResult.exceptionOrNull()),
          sendToClient,
        );
      }

      // Desregistra explicitamente no caminho de sucesso. `unregister` e
      // idempotente, entao nao colide com a limpeza tardia disparada por
      // `_onProgressChanged` quando o snapshot reportar `Concluído`. Sem
      // isso, o registry mantinha o contexto orfao caso o `progressNotifier`
      // nao publicasse o evento final por algum motivo (ex.: backup
      // sucedido sem snapshot terminal — cenario observado em testes).
      _executionRegistry.unregister(executionContext.runId);
    } on Object catch (e, st) {
      LoggerService.warningWithContext(
        'Execute schedule error',
        clientId: clientId,
        requestId: requestId.toString(),
        scheduleId: scheduleId,
        error: e,
        stackTrace: st,
      );
      if (progressSlotReserved) {
        _progressNotifier.failBackup(e.toString());
      }
      await sendToClient(
        clientId,
        createBackupFailedMessage(
          requestId: requestId,
          scheduleId: scheduleId,
          error: e.toString(),
          runId: executionContext?.runId,
        ),
      );
      if (executionContext != null) {
        _executionRegistry.unregister(executionContext.runId);
      }
    }
  }

  Future<void> _handleCancelSchedule(
    String clientId,
    int requestId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final scheduleId = getScheduleIdFromCancelRequest(message);
    if (scheduleId == null || scheduleId.isEmpty) {
      await _sendError(
        clientId,
        requestId,
        'scheduleId vazio ou inválido',
        sendToClient,
      );
      return;
    }

    final activeContext = _executionRegistry.getActiveByScheduleId(scheduleId);
    if (activeContext == null) {
      await _sendError(
        clientId,
        requestId,
        'Não há backup em execução para este schedule',
        sendToClient,
      );
      return;
    }

    LoggerService.infoWithContext(
      'Cancel schedule requested',
      clientId: clientId,
      requestId: requestId.toString(),
      scheduleId: scheduleId,
    );

    final cancelResult = await _schedulerService.cancelExecution(scheduleId);
    if (cancelResult.isError()) {
      await _sendError(
        clientId,
        requestId,
        _failureMessage(
          cancelResult.exceptionOrNull(),
          fallback: 'Falha ao cancelar backup',
        ),
        sendToClient,
      );
      return;
    }

    _executionRegistry.unregister(activeContext.runId);

    await sendToClient(
      clientId,
      createScheduleCancelledMessage(
        requestId: requestId,
        scheduleId: scheduleId,
      ),
    );
  }

  /// Helper para envio de erro padronizado. Antes era 14 cópias de
  /// `await sendToClient(clientId, createScheduleErrorMessage(...))` com
  /// pequenas variações. Centralizar evita divergência e facilita
  /// adicionar instrumentação (ex.: contar erros enviados).
  Future<void> _sendError(
    String clientId,
    int requestId,
    String error,
    SendToClient sendToClient,
  ) {
    return sendToClient(
      clientId,
      createScheduleErrorMessage(requestId: requestId, error: error),
    );
  }

  /// Extrai mensagem amigável de uma falha que veio do `Result.exceptionOrNull()`.
  /// Antes era `failure?.toString() ?? 'fallback'`, que para `Failure`
  /// gerava strings tipo `Failure(message: ..., code: null)` exibidas ao
  /// cliente — feio e expõe internals.
  String _failureMessage(Object? failure, {String fallback = 'Erro'}) {
    if (failure == null) return fallback;
    if (failure is Failure) {
      return failure.message.isEmpty ? fallback : failure.message;
    }
    final str = failure.toString();
    return str.isEmpty ? fallback : str;
  }
}
