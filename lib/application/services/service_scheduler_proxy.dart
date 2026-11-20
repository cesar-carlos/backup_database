import 'dart:async';
import 'dart:convert';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/service_connection_exception.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/execution_origin.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:uuid/uuid.dart';

typedef SchedulerRequest = Future<Map<String, dynamic>> Function(
  String command,
  String scheduleId,
);

/// Administrative UI has no local execution fallback, scheduling timers or cancellation
/// ownership. Closing it must never cancel work owned by the Windows service.
class ServiceSchedulerProxy implements ISchedulerService {
  ServiceSchedulerProxy(
    this.request, {
    this.progressNotifier,
    this.progressInterval = const Duration(seconds: 1),
    this.progressTimeout = const Duration(seconds: 5),
  });
  final IBackupProgressNotifier? progressNotifier;
  final Duration progressInterval;
  final Duration progressTimeout;
  Completer<Map<String, dynamic>>? _progressInterruption;
  int _lifecycle = 0;
  Timer? _progressTimer;
  Object? _progressSession;

  void _stopProgress() {
    _progressSession = null;
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _startProgress(String payload) {
    if (progressNotifier == null) return;
    _stopProgress();
    final session = Object();
    _progressSession = session;
    final identity = jsonDecode(payload) as Map<String, dynamic>;
    var inFlight = false;
    _progressTimer = Timer.periodic(progressInterval, (_) async {
      if (inFlight) return;
      inFlight = true;
      try {
        final reply = await request(
          'progress',
          payload,
        ).timeout(progressTimeout);
        if (!identical(_progressSession, session)) return;
        if (reply['code'] == 'service_restarted' &&
            reply['epoch'] is String &&
            reply['epoch'] != identity['epoch'] &&
            reply['requestId'] == identity['requestId'] &&
            reply['scheduleId'] == identity['scheduleId']) {
          final interruption = _progressInterruption;
          _stopProgress();
          if (interruption != null && !interruption.isCompleted) {
            interruption.complete({
              'ok': false,
              'uncertain': true,
              'error':
                  'O serviço reiniciou. Não foi possível confirmar o resultado '
                  'desta execução. Consulte o histórico antes de iniciar outro backup.',
            });
          }
          return;
        }
        if (reply['ok'] != true ||
            reply['epoch'] != identity['epoch'] ||
            reply['requestId'] != identity['requestId'] ||
            reply['scheduleId'] != identity['scheduleId']) {
          throw StateError('Progresso não confirmado');
        }
        final data = reply['progress'];
        if (data == null) {
          progressNotifier!.updateProgress(
            step: 'Iniciando',
            message: reply['completed'] == true
                ? 'Aguardando confirmação do resultado no serviço...'
                : 'Aguardando atualização do progresso no serviço...',
          );
          return;
        }
        if (data is! Map) throw const FormatException('Progresso inválido');
        final step = data['step'];
        final message = data['message'];
        final value = data['value'];
        if (step is! String ||
            message is! String ||
            (value != null && value is! num)) {
          throw const FormatException('Progresso inválido');
        }
        // Only the execute receipt can declare completion/failure. Cleanup
        // and notifications may still be running after the last progress event.
        if (step == 'Concluído' || step == 'Erro') return;
        progressNotifier!.updateProgress(
          step: step,
          message: message,
          progress: value is num && value.isFinite
              ? value.toDouble().clamp(0.0, 1.0)
              : null,
        );
      } on Object {
        if (identical(_progressSession, session)) {
          progressNotifier!.updateProgress(
            step: 'Iniciando',
            message:
                'Aguardando comunicação com o serviço. '
                'O backup pode continuar em execução...',
          );
        }
      } finally {
        inFlight = false;
      }
    });
  }

  final SchedulerRequest request;
  bool _supportsProgress = false;
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
    final lifecycle = _lifecycle;
    final interruption = Completer<Map<String, dynamic>>();
    _progressInterruption = interruption;
    final hadPreviousAttempt = _attempts.containsKey(scheduleId);
    var executeRequested = false;
    try {
      var payload = _attempts[scheduleId];
      if (payload == null) {
        final status = await Future.any([
          request('status', ''),
          interruption.future,
        ]);
        if (_suspended || lifecycle != _lifecycle) {
          return const rd.Failure(
            BackupFailure(
              message: 'Interface encerrando. Nenhum backup foi solicitado.',
            ),
          );
        }
        if (status['code'] == 'service_not_ready') {
          return const rd.Failure(
            BackupFailure(
              message:
                  'O serviço respondeu, mas o executor ainda não está pronto. '
                  'Aguarde a inicialização e tente novamente. Se persistir, '
                  'consulte os logs de inicialização do serviço. Nenhum backup foi solicitado.',
              code: 'service_not_ready',
            ),
          );
        }
        if (status['ok'] != true || status['epoch'] is! String) {
          return const rd.Failure(
            BackupFailure(
              message: 'Serviço indisponível ou incompatível. Nenhum backup foi solicitado.',
            ),
          );
        }
        _supportsProgress = status['progressVersion'] == 1;
        payload = jsonEncode({
          'scheduleId': scheduleId,
          'epoch': status['epoch'],
          'requestId': const Uuid().v4(),
        });
        _attempts[scheduleId] = payload;
      }
      executeRequested = true;
      if (_supportsProgress) _startProgress(payload);
      final response = await Future.any([
        request('execute', payload),
        interruption.future,
      ]);
      // Validate the entire receipt before discarding its idempotency key.
      // A malformed error/flag must not turn the next click into a new backup.
      if (response['ok'] is! bool ||
          (response.containsKey('uncertain') &&
              response['uncertain'] is! bool) ||
          (response.containsKey('confirmed') &&
              response['confirmed'] is! bool) ||
          (response['error'] != null && response['error'] is! String) ||
          (response['ok'] == true && response['uncertain'] == true)) {
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
    } on Object catch (e, s) {
      LoggerService.warning(
        'event=service_backup_request_failed scheduleId=$scheduleId '
        'executeRequested=$executeRequested previousAttempt=$hadPreviousAttempt',
        e,
        s,
      );
      if (!hadPreviousAttempt &&
          (!executeRequested || e is ServiceConnectionException)) {
        // Neither a failed handshake nor an unopened channel can start work.
        // Do not retain an old epoch for an operation that was never sent.
        _attempts.remove(scheduleId);
        return rd.Failure(
          BackupFailure(
            message:
                'Não foi possível conectar ao serviço de backup. '
                'Nenhum backup foi solicitado por esta tentativa. '
                'Abra Configurações > Serviço Windows e verifique o status. '
                'Se estiver parado, use Iniciar; se estiver iniciando, aguarde '
                'e tente novamente. Se estiver em execução, consulte os logs '
                'do serviço para identificar a falha de comunicação. '
                'Se o serviço não estiver instalado, feche a interface pelo '
                'menu Sair e abra novamente para refazer a detecção. '
                '${e is ServiceConnectionException && e.reason != null ? 'Diagnóstico: ${e.reason}' : ''}',
            code: 'service_unavailable_before_execution',
            originalError: e,
          ),
        );
      }
      // Keep the same identity after a lost/invalid reply. No automatic retry.
      return rd.Failure(
        BackupFailure(
          message:
              'Não foi possível confirmar a operação; ela pode continuar no serviço. '
              'Uma nova tentativa nesta interface consultará a mesma execução. $e',
          code: 'service_execution_unconfirmed',
          originalError: e,
        ),
      );
    } finally {
      _stopProgress();
      _progressInterruption = null;
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
  void stop() {
    _lifecycle++;
    _stopProgress();
    final interruption = _progressInterruption;
    if (interruption != null && !interruption.isCompleted) {
      interruption.complete({
        'ok': false,
        'uncertain': true,
        'error':
            'O acompanhamento foi encerrado nesta interface. '
            'O backup pode continuar no serviço; consulte o histórico antes de iniciar outra execução.',
      });
    }
  }

  @override
  void suspendExecutions() => _suspended = true;
  @override
  void resumeExecutions() => _suspended = false;
  @override
  Future<bool> waitForRunningBackups({
    Duration timeout = const Duration(minutes: 5),
  }) async => true;
}
