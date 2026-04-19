import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';

/// Handler de CRUD de schedule (PR-2): create, delete, pause, resume.
///
/// Separado de `ScheduleMessageHandler` para manter aquele com escopo
/// estrito de "execucao + listagem" e este com "mutacao de definicao".
/// Compartilham o `IScheduleRepository` e o `IdempotencyRegistry` via
/// DI para que comandos cruzados nao percam coerencia.
///
/// Operacoes mutaveis aceitam `idempotencyKey` opcional. Repeticao
/// dentro do TTL retorna a MESMA resposta cacheada — defesa contra
/// retransmissao por reconexao.
class ScheduleCrudMessageHandler {
  ScheduleCrudMessageHandler({
    required IScheduleRepository scheduleRepository,
    IdempotencyRegistry? idempotencyRegistry,
  })  : _scheduleRepository = scheduleRepository,
        _idempotencyRegistry = idempotencyRegistry ?? IdempotencyRegistry();

  final IScheduleRepository _scheduleRepository;
  final IdempotencyRegistry _idempotencyRegistry;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    final type = message.header.type;
    if (type != MessageType.createSchedule &&
        type != MessageType.deleteSchedule &&
        type != MessageType.pauseSchedule &&
        type != MessageType.resumeSchedule) {
      return;
    }

    final requestId = message.header.requestId;
    final idempotencyKey = getIdempotencyKey(message);

    try {
      final response = await _idempotencyRegistry.runIdempotent<Message>(
        key: idempotencyKey,
        compute: () => _dispatch(type, requestId, message),
      );
      await sendToClient(clientId, response);
    } on _CrudFailure catch (f) {
      // Falhas validacao/dominio NAO sao cacheadas (cliente pode
      // tentar de novo apos corrigir).
      await sendToClient(
        clientId,
        createErrorMessage(
          requestId: requestId,
          errorMessage: f.message,
          errorCode: f.errorCode,
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warningWithContext(
        'ScheduleCrudMessageHandler unexpected error',
        clientId: clientId,
        requestId: requestId.toString(),
        error: e,
        stackTrace: st,
      );
      await sendToClient(
        clientId,
        createErrorMessage(
          requestId: requestId,
          errorMessage: 'Erro interno: $e',
          errorCode: ErrorCode.unknown,
        ),
      );
    }
  }

  Future<Message> _dispatch(
    MessageType type,
    int requestId,
    Message message,
  ) async {
    switch (type) {
      case MessageType.createSchedule:
        return _doCreate(requestId, message);
      case MessageType.deleteSchedule:
        return _doDelete(requestId, message);
      case MessageType.pauseSchedule:
        return _doPause(requestId, message);
      case MessageType.resumeSchedule:
        return _doResume(requestId, message);
      case MessageType.authRequest:
      case MessageType.authResponse:
      case MessageType.authChallenge:
      case MessageType.listSchedules:
      case MessageType.scheduleList:
      case MessageType.updateSchedule:
      case MessageType.executeSchedule:
      case MessageType.scheduleUpdated:
      case MessageType.cancelSchedule:
      case MessageType.scheduleCancelled:
      case MessageType.backupProgress:
      case MessageType.backupStep:
      case MessageType.backupComplete:
      case MessageType.backupFailed:
      case MessageType.listFiles:
      case MessageType.fileList:
      case MessageType.fileTransferStart:
      case MessageType.fileChunk:
      case MessageType.fileTransferProgress:
      case MessageType.fileTransferComplete:
      case MessageType.fileTransferError:
      case MessageType.fileAck:
      case MessageType.metricsRequest:
      case MessageType.metricsResponse:
      case MessageType.heartbeat:
      case MessageType.disconnect:
      case MessageType.error:
      case MessageType.capabilitiesRequest:
      case MessageType.capabilitiesResponse:
      case MessageType.healthRequest:
      case MessageType.healthResponse:
      case MessageType.sessionRequest:
      case MessageType.sessionResponse:
      case MessageType.preflightRequest:
      case MessageType.preflightResponse:
      case MessageType.executionStatusRequest:
      case MessageType.executionStatusResponse:
      case MessageType.executionQueueRequest:
      case MessageType.executionQueueResponse:
      case MessageType.testDatabaseConnectionRequest:
      case MessageType.testDatabaseConnectionResponse:
      case MessageType.startBackupRequest:
      case MessageType.startBackupResponse:
      case MessageType.cancelBackupRequest:
      case MessageType.cancelBackupResponse:
      case MessageType.scheduleMutationResponse:
      case MessageType.listDatabaseConfigsRequest:
      case MessageType.listDatabaseConfigsResponse:
      case MessageType.createDatabaseConfigRequest:
      case MessageType.updateDatabaseConfigRequest:
      case MessageType.deleteDatabaseConfigRequest:
      case MessageType.databaseConfigMutationResponse:
        // Filtrado em `handle` antes de chegar aqui — defesa em
        // profundidade. Tipo nao deveria chegar a este switch.
        throw const _CrudFailure(
          'Tipo de mensagem nao suportado pelo CRUD',
          ErrorCode.invalidRequest,
        );
    }
  }

  Future<Message> _doCreate(int requestId, Message message) async {
    Schedule schedule;
    try {
      schedule = getScheduleFromCreatePayload(message);
    } on Object catch (e) {
      throw _CrudFailure(
        'Payload `schedule` invalido: $e',
        ErrorCode.invalidRequest,
      );
    }

    final result = await _scheduleRepository.create(schedule);
    final created = result.getOrNull();
    if (result.isError() || created == null) {
      throw _CrudFailure(
        'Falha ao criar agendamento: ${result.exceptionOrNull() ?? "desconhecido"}',
        ErrorCode.unknown,
      );
    }

    return createScheduleMutationResponse(
      requestId: requestId,
      operation: 'created',
      scheduleId: created.id,
      schedule: created,
    );
  }

  Future<Message> _doDelete(int requestId, Message message) async {
    final scheduleId = getScheduleIdFromMutationPayload(message);
    if (scheduleId.isEmpty) {
      throw const _CrudFailure(
        'scheduleId vazio',
        ErrorCode.invalidRequest,
      );
    }

    // Verifica existencia antes de tentar deletar — assim conseguimos
    // distinguir 404 (nao existe) de 500 (erro real ao deletar).
    final existsResult = await _scheduleRepository.getById(scheduleId);
    if (existsResult.isError()) {
      throw const _CrudFailure(
        'Agendamento nao encontrado',
        ErrorCode.scheduleNotFound,
      );
    }

    final result = await _scheduleRepository.delete(scheduleId);
    if (result.isError()) {
      throw _CrudFailure(
        'Falha ao deletar agendamento: ${result.exceptionOrNull() ?? "desconhecido"}',
        ErrorCode.unknown,
      );
    }

    return createScheduleMutationResponse(
      requestId: requestId,
      operation: 'deleted',
      scheduleId: scheduleId,
    );
  }

  /// pause/resume: muda flag `enabled` do schedule sem rodar regras
  /// adicionais (semantic identico a "togglar enabled" via UI). Em
  /// PR-3, isso podera evoluir para estados explicitos (`active`/
  /// `paused`/`disabled`) com validacao no scheduler — por enquanto,
  /// `enabled=false` e suficiente para impedir disparo automatico.
  Future<Message> _doPause(int requestId, Message message) =>
      _toggleEnabled(requestId, message, enabled: false, operation: 'paused');

  Future<Message> _doResume(int requestId, Message message) =>
      _toggleEnabled(requestId, message, enabled: true, operation: 'resumed');

  Future<Message> _toggleEnabled(
    int requestId,
    Message message, {
    required bool enabled,
    required String operation,
  }) async {
    final scheduleId = getScheduleIdFromMutationPayload(message);
    if (scheduleId.isEmpty) {
      throw const _CrudFailure(
        'scheduleId vazio',
        ErrorCode.invalidRequest,
      );
    }

    final getResult = await _scheduleRepository.getById(scheduleId);
    final current = getResult.getOrNull();
    if (getResult.isError() || current == null) {
      throw const _CrudFailure(
        'Agendamento nao encontrado',
        ErrorCode.scheduleNotFound,
      );
    }

    if (current.enabled == enabled) {
      // Idempotencia natural: ja esta no estado desejado. Responde
      // com o snapshot atual sem tocar no DB.
      return createScheduleMutationResponse(
        requestId: requestId,
        operation: operation,
        scheduleId: scheduleId,
        schedule: current,
      );
    }

    final updated = current.copyWith(enabled: enabled);
    final updateResult = await _scheduleRepository.update(updated);
    final result = updateResult.getOrNull();
    if (updateResult.isError() || result == null) {
      throw _CrudFailure(
        'Falha ao atualizar agendamento: ${updateResult.exceptionOrNull() ?? "desconhecido"}',
        ErrorCode.unknown,
      );
    }

    return createScheduleMutationResponse(
      requestId: requestId,
      operation: operation,
      scheduleId: scheduleId,
      schedule: result,
    );
  }
}

/// Excecao interna para sair cedo do `compute` do registry sem
/// cachear erro de validacao/dominio.
class _CrudFailure implements Exception {
  const _CrudFailure(this.message, this.errorCode);
  final String message;
  final ErrorCode errorCode;

  @override
  String toString() => 'CrudFailure(${errorCode.code}): $message';
}
