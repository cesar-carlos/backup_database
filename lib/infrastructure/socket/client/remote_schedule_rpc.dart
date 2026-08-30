import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/client/client_rpc_transport.dart';
import 'package:result_dart/result_dart.dart' as rd;

class RemoteScheduleRpc {
  RemoteScheduleRpc({
    required this._rpc,
    required this._isConnected,
    required this._send,
  });

  final ClientRpcTransport _rpc;
  final bool Function() _isConnected;
  final Future<void> Function(Message message) _send;

  Future<rd.Result<List<Schedule>>> listSchedules() {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createListSchedulesMessage(requestId: requestId),
      isExpected: (message) => message.header.type == MessageType.scheduleList,
      parse: getSchedulesFromListPayload,
      operationName: 'listSchedules',
      logFailures: true,
    );
  }

  Future<rd.Result<Schedule>> updateSchedule(Schedule schedule) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createUpdateScheduleMessage(
        requestId: requestId,
        schedule: schedule,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.scheduleUpdated,
      parse: getScheduleFromUpdatePayload,
      operationName: 'updateSchedule',
      logFailures: true,
    );
  }

  Future<rd.Result<ScheduleMutationResult>> createRemoteSchedule({
    required Schedule schedule,
    String? idempotencyKey,
  }) {
    return _runMutation(
      (requestId) => createCreateScheduleMessage(
        requestId: requestId,
        schedule: schedule,
        idempotencyKey: idempotencyKey,
      ),
      operationName: 'createSchedule',
    );
  }

  Future<rd.Result<ScheduleMutationResult>> deleteRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _runMutation(
      (requestId) => createDeleteScheduleMessage(
        requestId: requestId,
        scheduleId: scheduleId,
        idempotencyKey: idempotencyKey,
      ),
      operationName: 'deleteSchedule',
    );
  }

  Future<rd.Result<ScheduleMutationResult>> pauseRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _runMutation(
      (requestId) => createPauseScheduleMessage(
        requestId: requestId,
        scheduleId: scheduleId,
        idempotencyKey: idempotencyKey,
      ),
      operationName: 'pauseSchedule',
    );
  }

  Future<rd.Result<ScheduleMutationResult>> resumeRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) {
    return _runMutation(
      (requestId) => createResumeScheduleMessage(
        requestId: requestId,
        scheduleId: scheduleId,
        idempotencyKey: idempotencyKey,
      ),
      operationName: 'resumeSchedule',
    );
  }

  Future<rd.Result<void>> cancelSchedule(String scheduleId) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: (requestId) => createCancelScheduleMessage(
        requestId: requestId,
        scheduleId: scheduleId,
      ),
      isExpected: (message) =>
          message.header.type == MessageType.scheduleCancelled,
      parse: (_) => rd.unit,
      operationName: 'cancelSchedule',
    );
  }

  Future<rd.Result<ScheduleMutationResult>> _runMutation(
    Message Function(int requestId) build, {
    required String operationName,
  }) {
    return _rpc.request(
      isConnected: _isConnected(),
      send: _send,
      build: build,
      isExpected: isScheduleMutationResponseMessage,
      parse: readScheduleMutationResponse,
      operationName: operationName,
      unexpectedLabel: operationName,
    );
  }
}
