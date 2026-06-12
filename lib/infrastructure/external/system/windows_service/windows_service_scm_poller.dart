import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

typedef WindowsServiceStatusSupplier =
    Future<rd.Result<WindowsServiceStatus>> Function();

typedef WindowsServiceDiagnosticsSink =
    void Function(String message, {String? output});

class WindowsServiceScmPoller {
  WindowsServiceScmPoller({
    required WindowsServiceStatusSupplier getStatus,
    required WindowsServiceDiagnosticsSink appendDiagnostics,
  }) : _getStatus = getStatus,
       _appendDiagnostics = appendDiagnostics;

  final WindowsServiceStatusSupplier _getStatus;
  final WindowsServiceDiagnosticsSink _appendDiagnostics;

  static bool isServiceStopped(WindowsServiceStatus? status) {
    if (status == null) {
      return false;
    }
    if (!status.isInstalled) {
      return true;
    }
    return status.stateCode == WindowsServiceStateCode.stopped;
  }

  Future<bool> pollUntilRunning({
    required Duration timeout,
    required Duration interval,
    Duration initialDelay = Duration.zero,
    void Function(Duration)? onConvergence,
  }) async {
    final stopwatch = Stopwatch()..start();
    var pollCount = 0;
    if (initialDelay > Duration.zero) {
      await Future.delayed(initialDelay);
    }
    final deadline = DateTime.now().add(timeout);
    rd.Result<WindowsServiceStatus>? lastStatusResult;

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(interval);
      pollCount++;
      lastStatusResult = await _getStatus();
      final status = lastStatusResult.getOrNull();
      _appendDiagnostics(
        '_pollUntilRunning: poll=$pollCount installed=${status?.isInstalled} '
        'running=${status?.isRunning} state=${status?.stateCode?.name}',
      );
      if (status?.isRunning ?? false) {
        onConvergence?.call(stopwatch.elapsed);
        _appendDiagnostics(
          '_pollUntilRunning: converged in ${stopwatch.elapsedMilliseconds}ms',
        );
        return true;
      }
    }

    if (lastStatusResult != null) {
      final lastStatus = lastStatusResult.getOrNull();
      LoggerService.warning(
        'Timeout ao aguardar RUNNING. Último status: '
        'isInstalled=${lastStatus?.isInstalled}, '
        'isRunning=${lastStatus?.isRunning}, '
        'stateCode=${lastStatus?.stateCode?.name}',
      );
      _appendDiagnostics(
        '_pollUntilRunning: timeout after ${stopwatch.elapsedMilliseconds}ms '
        'lastState=${lastStatus?.stateCode?.name}',
      );
    }
    return false;
  }

  Future<bool> pollUntilStopped({
    required Duration timeout,
    required Duration interval,
    void Function(Duration)? onConvergence,
  }) async {
    final stopwatch = Stopwatch()..start();
    var pollCount = 0;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(interval);
      pollCount++;
      final statusResult = await _getStatus();
      final status = statusResult.getOrNull();
      _appendDiagnostics(
        '_pollUntilStopped: poll=$pollCount installed=${status?.isInstalled} '
        'running=${status?.isRunning} state=${status?.stateCode?.name}',
      );
      if (isServiceStopped(status)) {
        onConvergence?.call(stopwatch.elapsed);
        _appendDiagnostics(
          '_pollUntilStopped: converged in ${stopwatch.elapsedMilliseconds}ms',
        );
        return true;
      }
    }
    _appendDiagnostics(
      '_pollUntilStopped: timeout after ${stopwatch.elapsedMilliseconds}ms',
    );
    return false;
  }
}
