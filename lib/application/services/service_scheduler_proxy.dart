import 'dart:convert';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/execution_origin.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:uuid/uuid.dart';

typedef SchedulerRequest = Future<Map<String, dynamic>> Function(
  String command,
  String scheduleId,
);

/// Administrative UI has no local execution fallback, timers or cancellation
/// ownership. Closing it must never cancel work owned by the Windows service.
class ServiceSchedulerProxy implements ISchedulerService {
  ServiceSchedulerProxy(this.request);
  final SchedulerRequest request;
  bool _pending = false;
  bool _suspended = false;
  String? activeScheduleId;
  final Map<String, String> _attempts = {};

  @override
  bool get isExecutingBackup => _pending;
  @override
  bool get isRunning => false;

  Future<rd.Result<void>> _send(String command, String id) async {
    try {
      final response = await request(command, id);
      if (response['ok'] == true) return const rd.Success(rd.unit);
      return rd.Failure(
        BackupFailure(
          message: response['error'] as String? ?? 'Falha no serviço de backup',
        ),
      );
    } on Object catch (e) {
      return rd.Failure(
        BackupFailure(
          message:
              'Não foi possível confirmar a operação no serviço. '
              'Ela pode continuar em execução; consulte os logs antes de repetir. $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> executeNow(
    String scheduleId, {
    ExecutionOrigin executionOrigin = ExecutionOrigin.local,
    String? runId,
  }) async {
    if (_pending || _suspended) {
      return const rd.Failure(
        BackupFailure(message: 'Execução indisponível nesta interface'),
      );
    }
    _pending = true;
    activeScheduleId = scheduleId;
    try {
      var payload = _attempts[scheduleId];
      if (payload == null) {
        final status = await request('status', '');
        if (status['ok'] != true || status['epoch'] is! String) {
          return const rd.Failure(
            BackupFailure(
              message: 'Serviço indisponível ou incompatível. Nenhum backup foi solicitado.',
            ),
          );
        }
        if (_suspended) {
          return const rd.Failure(
            BackupFailure(
              message: 'Interface encerrando. Nenhum backup foi solicitado.',
            ),
          );
        }
        payload = jsonEncode({
          'scheduleId': scheduleId,
          'epoch': status['epoch'],
          'requestId': const Uuid().v4(),
        });
        _attempts[scheduleId] = payload;
      }
      final response = await request('execute', payload);
      if (response['ok'] is! bool) {
        throw StateError('Resposta inválida do serviço');
      }
      if (response['uncertain'] != true &&
          (response['ok'] == true || response['confirmed'] == true)) {
        _attempts.remove(scheduleId);
      }
      if (response['ok'] == true) return const rd.Success(rd.unit);
      return rd.Failure(
        BackupFailure(
          message: response['error'] as String? ?? 'Falha no serviço',
        ),
      );
    } on Object catch (e) {
      // Keep the same identity after a lost/invalid reply. No automatic retry.
      return rd.Failure(
        BackupFailure(
          message:
              'Não foi possível confirmar a operação; ela pode continuar no serviço. '
              'Uma nova tentativa nesta interface consultará a mesma execução. $e',
        ),
      );
    } finally {
      _pending = false;
      activeScheduleId = null;
    }
  }

  Future<bool> isServiceIdle() async {
    try {
      final response = await request('status', '');
      return response['ok'] == true && response['busy'] == false;
    } on Object {
      return false;
    }
  }

  @override
  Future<rd.Result<void>> cancelExecution(String id) {
    final attempt = _attempts[id];
    if (attempt == null) {
      return Future.value(
        const rd.Failure(
          BackupFailure(
            message: 'Não existe execução identificada por esta interface para cancelar.',
          ),
        ),
      );
    }
    return _send('cancel', attempt);
  }

  @override
  Future<rd.Result<void>> refreshSchedule(String id) => _send('refresh', id);
  @override
  Future<void> start() async {}
  @override
  void stop() {}
  @override
  void suspendExecutions() => _suspended = true;
  @override
  void resumeExecutions() => _suspended = false;
  @override
  Future<bool> waitForRunningBackups({
    Duration timeout = const Duration(minutes: 5),
  }) async => true;
}
