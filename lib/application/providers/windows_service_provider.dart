import 'dart:developer' as developer;

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_windows_service_event_logger.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:flutter/foundation.dart';

enum WindowsServiceOperation {
  none,
  check,
  install,
  uninstall,
  start,
  stop,
  restart,
}

enum WindowsServiceInstallOutcome {
  failed,
  registeredAndRunning,
  registeredBlockedByUiInstance,
  registeredStartFailed,
}

class WindowsServiceProvider extends ChangeNotifier with AsyncStateMixin {
  WindowsServiceProvider(
    this._service,
    this._eventLog, {
    IMetricsCollector? metricsCollector,
  }) : _metrics = metricsCollector {
    _service.setElevationWaitListener(_handleElevationWait);
  }
  final IWindowsServiceService _service;
  final IWindowsServiceEventLogger _eventLog;
  final IMetricsCollector? _metrics;

  WindowsServiceStatus? _status;
  WindowsServiceOperation _operation = WindowsServiceOperation.none;
  bool _isWaitingForUac = false;

  WindowsServiceStatus? _statusCache;
  DateTime? _statusCacheTimestamp;
  static const _statusCacheTtl = Duration(seconds: 2);

  // startPollingTimeout (30s) + startPollingInitialDelay (3s)
  static const Duration _scmStartEventLogTimeout = Duration(seconds: 33);

  // S15: dispose-aware. Embora o provider não possua timers nem
  // subscriptions explícitas, operações async em curso (`installService`,
  // etc.) podem completar após dispose se o usuário fechar a tela. Sem
  // este guard, `notifyListeners` post-dispose lança em produção.
  bool _isDisposed = false;

  WindowsServiceStatus? get status => _status;
  bool get isStarting =>
      _operation == WindowsServiceOperation.start ||
      _operation == WindowsServiceOperation.restart;
  WindowsServiceOperation get operation => _operation;
  bool get isInstalled => _status?.isInstalled ?? false;
  bool get isRunning => _status?.isRunning ?? false;
  bool get isWaitingForUac => _isWaitingForUac;
  WindowsServiceStateCode? get stateCode => _status?.stateCode;
  bool get isStopPending => stateCode == WindowsServiceStateCode.stopPending;
  bool get isStartPending => stateCode == WindowsServiceStateCode.startPending;

  void _handleElevationWait(bool waiting) {
    if (_isDisposed) {
      return;
    }
    if (_isWaitingForUac == waiting) {
      return;
    }
    _isWaitingForUac = waiting;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _service.setElevationWaitListener(null);
    super.dispose();
  }

  Future<void> checkStatus({bool forceRefresh = false}) async {
    if (isLoading && !forceRefresh) {
      developer.log(
        'checkStatus skipped: operation in progress',
        name: 'WindowsServiceProvider',
      );
      return;
    }

    final cacheValid =
        !forceRefresh &&
        _statusCache != null &&
        _statusCacheTimestamp != null &&
        DateTime.now().difference(_statusCacheTimestamp!) < _statusCacheTtl;

    if (cacheValid) {
      _status = _statusCache;
      clearError();
      notifyListeners();
      return;
    }

    await _runOperation(WindowsServiceOperation.check, () async {
      final result = await _service.getStatus();
      result.fold(
        (status) {
          _status = status;
          _statusCache = status;
          _statusCacheTimestamp = DateTime.now();
        },
        (failure) {
          _statusCache = null;
          _statusCacheTimestamp = null;
          throw failure;
        },
      );
    });
  }

  void _invalidateStatusCache() {
    _statusCache = null;
    _statusCacheTimestamp = null;
  }

  Future<WindowsServiceInstallOutcome> installService({
    String? user,
    String? password,
  }) async {
    if (isLoading) return WindowsServiceInstallOutcome.failed;
    await _eventLog.logInstallStarted();

    final installToRunningWatch = Stopwatch()..start();

    final success = await _runOperation<bool>(
      WindowsServiceOperation.install,
      () async {
        final result = await _service.installService(
          serviceUser: user,
          servicePassword: password,
        );
        return result.fold(
          (_) => true,
          (failure) => throw failure,
        );
      },
    );

    final registered = success ?? false;
    if (!registered) {
      await _eventLog.logInstallFailed(error: error ?? 'Erro desconhecido');
      return WindowsServiceInstallOutcome.failed;
    }

    await _eventLog.logInstallSucceeded();
    final started = await startService();
    if (started && (_status?.isRunning ?? false)) {
      installToRunningWatch.stop();
      _metrics?.recordHistogram(
        ObservabilityMetrics.windowsServiceInstallToRunningSeconds,
        installToRunningWatch.elapsedMilliseconds / 1000,
      );
      return WindowsServiceInstallOutcome.registeredAndRunning;
    }

    if (!started && _isLockBlockedStartFailure(error)) {
      _metrics?.incrementCounter(
        ObservabilityMetrics.windowsServiceInstallBlockedByUiInstance,
      );
      return WindowsServiceInstallOutcome.registeredBlockedByUiInstance;
    }

    return WindowsServiceInstallOutcome.registeredStartFailed;
  }

  Future<bool> scheduleStartAfterUiExit() async {
    if (isLoading) return false;
    final success = await _runOperation<bool>(
      WindowsServiceOperation.start,
      () async {
        final result = await _service.scheduleStartAfterUiExit();
        return result.fold(
          (_) => true,
          (failure) => throw failure,
        );
      },
    );
    return success ?? false;
  }

  static bool _isLockBlockedStartFailure(String? message) {
    if (message == null || message.isEmpty) {
      return true;
    }
    final lower = message.toLowerCase();
    if (lower.contains('acesso negado') ||
        lower.contains('access denied') ||
        lower.contains('uac') ||
        lower.contains('cancelad')) {
      return false;
    }
    if (lower.contains('single_instance_lock') ||
        lower.contains('lockdenied') ||
        lower.contains('lock denied') ||
        lower.contains('exit 77') ||
        lower.contains('código 77') ||
        lower.contains('codigo 77')) {
      return true;
    }
    return lower.contains('não atingiu') ||
        lower.contains('nao atingiu') ||
        lower.contains('dentro do tempo esperado') ||
        lower.contains('tempo esperado');
  }

  Future<bool> uninstallService() async {
    if (isLoading) return false;
    await _eventLog.logUninstallStarted();

    final success = await _runOperation<bool>(
      WindowsServiceOperation.uninstall,
      () async {
        final result = await _service.uninstallService();
        return result.fold(
          (_) => true,
          (failure) => throw failure,
        );
      },
    );

    final ok = success ?? false;
    if (ok) {
      await _eventLog.logUninstallSucceeded();
      _invalidateStatusCache();
      await _refreshStatusSilently();
    } else {
      await _eventLog.logUninstallFailed(error: error ?? 'Erro desconhecido');
    }
    return ok;
  }

  Future<bool> startService() async {
    if (isLoading) return false;
    await _eventLog.logStartStarted();

    final success = await _runOperation<bool>(
      WindowsServiceOperation.start,
      () async {
        final result = await _service.startService();
        return result.fold(
          (_) => true,
          (failure) => throw failure,
        );
      },
    );

    final ok = success ?? false;
    if (ok) {
      await _eventLog.logStartSucceeded();
    } else {
      await _logStartFailureOrTimeout();
    }

    _invalidateStatusCache();
    await _refreshStatusSilently();
    return ok;
  }

  Future<void> _logStartFailureOrTimeout() async {
    final err = error ?? '';
    if (_isTimeoutMessage(err)) {
      await _eventLog.logStartTimeout(timeout: _scmStartEventLogTimeout);
    } else {
      await _eventLog.logStartFailed(error: err);
    }
  }

  Future<void> _logStopFailureOrTimeout() async {
    final err = error ?? '';
    if (_isTimeoutMessage(err)) {
      await _eventLog.logStopTimeout(timeout: _scmStartEventLogTimeout);
    } else {
      await _eventLog.logStopFailed(error: err);
    }
  }

  static bool _isTimeoutMessage(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('timeout') ||
        lower.contains('tempo esgotado') ||
        lower.contains('tempo esperado') ||
        lower.contains('não atingiu') ||
        lower.contains('nao atingiu');
  }

  Future<bool> stopService() async {
    if (isLoading) return false;
    await _eventLog.logStopStarted();

    final success = await _runOperation<bool>(
      WindowsServiceOperation.stop,
      () async {
        final result = await _service.stopService();
        return result.fold(
          (_) => true,
          (failure) => throw failure,
        );
      },
    );

    final ok = success ?? false;
    if (ok) {
      await _eventLog.logStopSucceeded();
    } else {
      await _logStopFailureOrTimeout();
    }

    _invalidateStatusCache();
    await _refreshStatusSilently();
    return ok;
  }

  Future<bool> restartService() async {
    if (isLoading) return false;
    await _eventLog.logStopStarted();
    await _eventLog.logStartStarted();

    final success = await _runOperation<bool>(
      WindowsServiceOperation.restart,
      () async {
        final result = await _service.restartService();
        return result.fold(
          (_) => true,
          (failure) => throw failure,
        );
      },
    );

    final ok = success ?? false;
    if (ok) {
      await _eventLog.logStopSucceeded();
      await _eventLog.logStartSucceeded();
    } else {
      await _logStartFailureOrTimeout();
    }

    _invalidateStatusCache();
    await _refreshStatusSilently();
    return ok;
  }

  /// Wrapper específico que adicionalmente seta `_operation` para que a
  /// UI possa diferenciar (start/stop/restart/install/uninstall/check).
  /// Delega a gestão de `isLoading` + `error` ao [runAsync] do mixin.
  Future<T?> _runOperation<T>(
    WindowsServiceOperation op,
    Future<T> Function() action,
  ) async {
    _operation = op;
    notifyListeners();
    try {
      return await runAsync<T>(action: action);
    } finally {
      _operation = WindowsServiceOperation.none;
      notifyListeners();
    }
  }

  /// Atualiza `_status` consultando o SCM e notifica listeners se houve
  /// mudança real. Usado após operações `start`/`stop`/`restart` para
  /// refletir o estado convergido sem disparar nova flag de loading.
  ///
  /// Antes desse método terminar com `notifyListeners()` explícito no
  /// caller, cada operação chamava `notifyListeners()` 3-5x: `_runOperation`
  /// no início e fim + `runAsync` interno + um extra após o refresh
  /// (issue §3.7). Agora consolidamos em uma única notificação aqui,
  /// disparada **só se o status realmente mudou**.
  Future<void> _refreshStatusSilently() async {
    final result = await _service.getStatus();
    result.fold(
      (status) {
        final changed =
            _status?.isInstalled != status.isInstalled ||
            _status?.isRunning != status.isRunning ||
            _status?.stateCode != status.stateCode;
        _status = status;
        _statusCache = status;
        _statusCacheTimestamp = DateTime.now();
        if (changed) {
          notifyListeners();
        }
      },
      (_) {},
    );
  }
}
