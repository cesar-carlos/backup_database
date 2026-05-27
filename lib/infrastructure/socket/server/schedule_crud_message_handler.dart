import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_policy.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/socket/server/socket_error_sender.dart';

/// Handler de CRUD de schedule (PR-2): create, delete, pause, resume.
///
/// Separado de `ScheduleMessageHandler` para manter aquele com escopo
/// estrito de "execucao + listagem" e este com "mutacao de definicao".
/// Compartilham o `IScheduleRepository` e o `IdempotencyRegistry` via
/// DI para que comandos cruzados nao percam coerencia.
///
/// Operacoes mutaveis exigem `idempotencyKey` ([IdempotencyPolicy]).
/// Repeticao dentro do TTL retorna a MESMA resposta cacheada — defesa
/// contra retransmissao por reconexao. Falhas de validacao/dominio nao
/// sao cacheadas.
class ScheduleCrudMessageHandler {
  ScheduleCrudMessageHandler({
    required IScheduleRepository scheduleRepository,
    IdempotencyRegistry? idempotencyRegistry,
    bool supportsFirebird = true,
  }) : _scheduleRepository = scheduleRepository,
       _idempotencyRegistry = idempotencyRegistry ?? IdempotencyRegistry(),
       _supportsFirebird = supportsFirebird;

  final IScheduleRepository _scheduleRepository;
  final IdempotencyRegistry _idempotencyRegistry;
  final bool _supportsFirebird;

  // Map estático de operações CRUD. Antes era um `switch` exaustivo
  // com 60+ enum cases que caíam todos no mesmo `throw _CrudFailure`,
  // só para satisfazer o exhaustiveness checker. Como `handle` já
  // filtra os tipos válidos antes de chegar aqui, este map cobre os
  // 4 reais; tipos inesperados disparam o `throw` no `_dispatch`.
  late final Map<MessageType, Future<Message> Function(int, Message)>
  _operations = <MessageType, Future<Message> Function(int, Message)>{
    MessageType.createSchedule: _doCreate,
    MessageType.deleteSchedule: _doDelete,
    MessageType.pauseSchedule: _doPause,
    MessageType.resumeSchedule: _doResume,
  };

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
    final keyError = IdempotencyPolicy.missingKeyErrorMessage(
      message: message,
      operationType: type,
    );
    if (keyError != null) {
      await sendToClient(clientId, keyError);
      return;
    }

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
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: f.message,
        sendToClient: sendToClient,
        errorCode: f.errorCode,
      );
    } on Object catch (e, st) {
      LoggerService.warningWithContext(
        'ScheduleCrudMessageHandler unexpected error',
        clientId: clientId,
        requestId: requestId.toString(),
        error: e,
        stackTrace: st,
      );
      await SocketErrorSender.sendProtocolError(
        clientId: clientId,
        requestId: requestId,
        errorMessage: 'Erro interno: $e',
        sendToClient: sendToClient,
        errorCode: ErrorCode.unknown,
      );
    }
  }

  Future<Message> _dispatch(
    MessageType type,
    int requestId,
    Message message,
  ) {
    final operation = _operations[type];
    if (operation == null) {
      // Filtrado em `handle` antes de chegar aqui — defesa em
      // profundidade. Tipo nao deveria chegar a este dispatch.
      throw const _CrudFailure(
        'Tipo de mensagem nao suportado pelo CRUD',
        ErrorCode.invalidRequest,
      );
    }
    return operation(requestId, message);
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

    if (schedule.databaseType == DatabaseType.firebird && !_supportsFirebird) {
      throw _CrudFailure(
        ErrorCode.unsupportedDatabaseType.defaultMessage,
        ErrorCode.unsupportedDatabaseType,
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

  /// Extrai e valida `scheduleId` do payload de mutação. Lança
  /// [_CrudFailure] com `invalidRequest` quando ausente/vazio — antes
  /// duplicado in-line nos dois sites (`_doDelete` e `_toggleEnabled`).
  String _requireMutationScheduleId(Message message) {
    final scheduleId = getScheduleIdFromMutationPayload(message);
    if (scheduleId.isEmpty) {
      throw const _CrudFailure(
        'scheduleId vazio',
        ErrorCode.invalidRequest,
      );
    }
    return scheduleId;
  }

  Future<Message> _doDelete(int requestId, Message message) async {
    final scheduleId = _requireMutationScheduleId(message);

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
    final scheduleId = _requireMutationScheduleId(message);

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
