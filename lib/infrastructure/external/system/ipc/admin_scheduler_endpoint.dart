import 'dart:async';
import 'dart:convert';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/uuid_validator.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:uuid/uuid.dart';

/// Requests are scoped to one executor lifetime. Never evict receipts within
/// that lifetime: a delayed retry must not become a new execution.
class AdminSchedulerEndpoint {
  AdminSchedulerEndpoint({
    this.maxReceipts = 4096,
    void Function(String, Object, StackTrace)? logError,
  }) : _logError = logError ?? LoggerService.error;
  final int maxReceipts;
  final void Function(String, Object, StackTrace) _logError;
  ISchedulerService? scheduler;
  String _epoch = const Uuid().v4();
  final Map<String, _Receipt> _receipts = {};

  void newGeneration() {
    _epoch = const Uuid().v4();
    _receipts.clear();
  }

  Future<Map<String, dynamic>> dispatch(String command, String payload) async {
    final target = scheduler;
    if (target == null) {
      return {
        ..._error('Executor indisponível'),
        'code': 'service_not_ready',
        'uncertain': true,
      };
    }
    if (command == 'status') {
      return {
        'ok': true,
        'busy': target.isExecutingBackup,
        'epoch': _epoch,
        'progressVersion': target is IScopedBackupProgress ? 1 : 0,
      };
    }
    if (command == 'refresh' && UuidValidator.isValid(payload)) {
      return _result(
        () => target.refreshSchedule(payload),
        context: 'command=refresh scheduleId=$payload',
      );
    }
    if (command != 'execute' && command != 'cancel' && command != 'progress') {
      return _error('Comando inválido');
    }
    Map<String, dynamic> args;
    try {
      args = jsonDecode(payload) as Map<String, dynamic>;
    } on Object {
      return _error('Comando sem identificação de execução');
    }
    final id = args['scheduleId'];
    final requestId = args['requestId'];
    if (id is! String ||
        requestId is! String ||
        !UuidValidator.isValid(id) ||
        !UuidValidator.isValid(requestId)) {
      return _error('Identificação inválida');
    }
    if (args['epoch'] != _epoch) {
      return {
        ..._error(
          'O serviço reiniciou. Confira o histórico antes de iniciar outra execução.',
        ),
        'uncertain': true,
        'code': 'service_restarted',
        'epoch': _epoch,
        'scheduleId': id,
        'requestId': requestId,
      };
    }
    final receipt = _receipts[requestId];
    if (receipt != null && receipt.scheduleId != id) {
      return _error('Identificador reutilizado para outro agendamento');
    }
    if (command == 'progress') {
      if (receipt == null) return _error('Execução ainda não registrada');
      final snapshot = !receipt.completed && target is IScopedBackupProgress
          ? (target as IScopedBackupProgress).progressForRun(id, requestId)
          : null;
      return {
        'ok': true,
        'epoch': _epoch,
        'requestId': requestId,
        'scheduleId': id,
        'completed': receipt.completed,
        'progress': snapshot == null
            ? null
            : {
                'step': snapshot.step,
                'message': snapshot.message,
                'value': (snapshot.progress?.isFinite ?? false)
                    ? snapshot.progress
                    : null,
              },
      };
    }
    if (command == 'cancel') {
      if (receipt == null || receipt.completed) {
        return _error('A execução indicada não está ativa');
      }
      if (target is! IScopedBackupCancellation) {
        return _error('Cancelamento identificado indisponível');
      }
      return _result(
        () => (target as IScopedBackupCancellation).cancelRun(id, requestId),
        context: 'command=cancel scheduleId=$id requestId=$requestId',
      );
    }
    if (receipt != null) return receipt.result;
    if (_receipts.length >= maxReceipts) {
      return _error(
        'Limite de comandos administrativos atingido. Reinicie o serviço quando não houver backups ativos.',
      );
    }
    // Register before invoking any asynchronous executor code.
    final created = _Receipt(id);
    _receipts[requestId] = created;
    final result = await _result(
      () => target.executeNow(id, runId: requestId),
      context: 'command=execute scheduleId=$id requestId=$requestId',
    );
    created.completed = true;
    created.completion.complete(result);
    return result;
  }

  Future<Map<String, dynamic>> _result(
    Future<rd.Result<void>> Function() action, {
    required String context,
  }) async {
    try {
      final result = await action();
      return result.fold<Map<String, dynamic>>(
        (_) => {'ok': true},
        (error) => {..._error(failureUserMessage(error)), 'confirmed': true},
      );
    } on Object catch (e, s) {
      _logError('event=ipc_executor_exception $context', e, s);
      return {
        ..._error('Falha no executor; consulte os logs'),
        'uncertain': true,
      };
    }
  }

  Map<String, dynamic> _error(String text) => {'ok': false, 'error': text};
}

class _Receipt {
  _Receipt(this.scheduleId);
  final String scheduleId;
  final completion = Completer<Map<String, dynamic>>();
  Future<Map<String, dynamic>> get result => completion.future;
  bool completed = false;
}
