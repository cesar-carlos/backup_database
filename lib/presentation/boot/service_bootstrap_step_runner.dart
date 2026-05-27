import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/boot/service_bootstrap_log.dart';

class ServiceBootstrapStepRunner {
  ServiceBootstrapStepRunner({
    required this.totalSteps,
    required ServiceBootstrapLog log,
  }) : _log = log;

  final int totalSteps;
  final ServiceBootstrapLog _log;

  Future<void> run({
    required int step,
    required String label,
    required Future<void> Function() action,
    String Function()? successDetails,
  }) async {
    final tag = '[$step/$totalSteps]';
    LoggerService.info('>>> $tag $label...');
    await _log.append('step $step/$totalSteps: $label begin');
    try {
      await action();
      final details = successDetails?.call();
      LoggerService.info('>>> $tag OK $label');
      await _log.append(
        'step $step/$totalSteps: $label success'
        '${details != null ? ' ($details)' : ''}',
      );
    } on Object catch (e, s) {
      await _log.append(
        'step $step/$totalSteps: $label failed',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  Future<void> markAborted({
    required int step,
    required String reason,
    required int exitCode,
  }) {
    return _log.append(
      'step $step/$totalSteps: aborted reason=$reason exit=$exitCode',
    );
  }
}
