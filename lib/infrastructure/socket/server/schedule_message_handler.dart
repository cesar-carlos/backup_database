import 'package:backup_database/core/errors/failure.dart';
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

typedef SendToClient = Future<void> Function(String clientId, Message message);

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
  }) : _scheduleRepository = scheduleRepository,
       _destinationRepository = destinationRepository,
       _licensePolicyService = licensePolicyService,
       _schedulerService = schedulerService,
       _updateSchedule = updateSchedule,
       _executeBackup = executeBackup,
       _progressNotifier = progressNotifier {
    _progressNotifier.addListener(_onProgressChanged);
  }

  final IScheduleRepository _scheduleRepository;
  final IBackupDestinationRepository _destinationRepository;
  final ILicensePolicyService _licensePolicyService;
  final ISchedulerService _schedulerService;
  final UpdateSchedule _updateSchedule;
  final ExecuteScheduledBackup _executeBackup;
  final IBackupProgressNotifier _progressNotifier;

  String? _currentClientId;
  int? _currentRequestId;
  String? _currentScheduleId;
  SendToClient? _sendToClient;

  void dispose() {
    _progressNotifier.removeListener(_onProgressChanged);
  }

  Future<void> _onProgressChanged() async {
    if (_currentClientId == null ||
        _currentRequestId == null ||
        _currentScheduleId == null ||
        _sendToClient == null) {
      return;
    }

    final snapshot = _progressNotifier.currentSnapshot;
    if (snapshot == null) return;

    final progressValue = snapshot.progress ?? 0.0;

    // AGUARDAR o envio da primeira mensagem completar antes de continuar
    await _sendToClient!(
      _currentClientId!,
      createBackupProgressMessage(
        requestId: _currentRequestId!,
        scheduleId: _currentScheduleId!,
        step: snapshot.step,
        message: snapshot.message,
        progress: progressValue,
      ),
    );

    if (snapshot.step == 'Concluído') {
      LoggerService.debug(
        '[ScheduleMessageHandler] backupComplete backupPath='
        '${snapshot.backupPath == null || snapshot.backupPath!.isEmpty ? "(empty)" : "(set)"}',
      );

      await _sendToClient!(
        _currentClientId!,
        createBackupCompleteMessage(
          requestId: _currentRequestId!,
          scheduleId: _currentScheduleId!,
          message: snapshot.message,
          backupPath: snapshot.backupPath,
        ),
      );
      _clearCurrentBackup();
    } else if (snapshot.step == 'Erro') {
      await _sendToClient!(
        _currentClientId!,
        createBackupFailedMessage(
          requestId: _currentRequestId!,
          scheduleId: _currentScheduleId!,
          error: snapshot.error ?? 'Erro desconhecido',
        ),
      );
      _clearCurrentBackup();
    }
  }

  void _clearCurrentBackup() {
    _currentClientId = null;
    _currentRequestId = null;
    _currentScheduleId = null;
    _sendToClient = null;
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

    LoggerService.infoWithContext(
      'Execute schedule started',
      clientId: clientId,
      requestId: requestId.toString(),
      scheduleId: scheduleId,
    );

    var progressSlotReserved = false;
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

      _currentClientId = clientId;
      _currentRequestId = requestId;
      _currentScheduleId = scheduleId;
      _sendToClient = sendToClient;

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

      if (_currentClientId == null) return;

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
        _clearCurrentBackup();
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
        ),
      );
      _clearCurrentBackup();
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

    // Só pode cancelar o backup do cliente atual
    if (scheduleId != _currentScheduleId) {
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

    _clearCurrentBackup();

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
