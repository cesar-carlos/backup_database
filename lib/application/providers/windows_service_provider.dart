import 'package:backup_database/application/providers/async_state_mixin.dart';
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

class WindowsServiceProvider extends ChangeNotifier with AsyncStateMixin {
  WindowsServiceProvider(this._service, this._eventLog);
  final IWindowsServiceService _service;
  final IWindowsServiceEventLogger _eventLog;

  WindowsServiceStatus? _status;
  WindowsServiceOperation _operation = WindowsServiceOperation.none;

  WindowsServiceStatus? _statusCache;
  DateTime? _statusCacheTimestamp;
  static const _statusCacheTtl = Duration(seconds: 2);

  WindowsServiceStatus? get status => _status;
  bool get isStarting =>
      _operation == WindowsServiceOperation.start ||
      _operation == WindowsServiceOperation.restart;
  WindowsServiceOperation get operation => _operation;
  bool get isInstalled => _status?.isInstalled ?? false;
  bool get isRunning => _status?.isRunning ?? false;

  Future<void> checkStatus({bool forceRefresh = false}) async {
    if (isLoading) return;

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

  Future<bool> installService({String? user, String? password}) async {
    if (isLoading) return false;
    await _eventLog.logInstallStarted();

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

    final ok = success ?? false;
    if (ok) {
      await _eventLog.logInstallSucceeded();
      _invalidateStatusCache();
      await checkStatus(forceRefresh: true);
    } else {
      await _eventLog.logInstallFailed(error: error ?? 'Erro desconhecido');
    }
    return ok;
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
      await checkStatus(forceRefresh: true);
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
      final err = error ?? '';
      if (_isTimeoutMessage(err)) {
        await _eventLog.logStartTimeout(
          timeout: const Duration(seconds: 60),
        );
      } else {
        await _eventLog.logStartFailed(error: err);
      }
    }

    _invalidateStatusCache();
    await _refreshStatusSilently();
    notifyListeners();
    return ok;
  }

  static bool _isTimeoutMessage(String msg) =>
      msg.toLowerCase().contains('timeout') ||
      msg.toLowerCase().contains('tempo esgotado');

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
      final err = error ?? '';
      if (_isTimeoutMessage(err)) {
        await _eventLog.logStopTimeout(
          timeout: const Duration(seconds: 60),
        );
      } else {
        await _eventLog.logStopFailed(error: err);
      }
    }

    _invalidateStatusCache();
    await _refreshStatusSilently();
    notifyListeners();
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
      final err = error ?? '';
      if (_isTimeoutMessage(err)) {
        await _eventLog.logStartTimeout(
          timeout: const Duration(seconds: 60),
        );
      } else {
        await _eventLog.logStartFailed(error: err);
      }
    }

    _invalidateStatusCache();
    await _refreshStatusSilently();
    notifyListeners();
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

  Future<void> _refreshStatusSilently() async {
    final result = await _service.getStatus();
    result.fold(
      (status) {
        _status = status;
        _statusCache = status;
        _statusCacheTimestamp = DateTime.now();
      },
      (_) {},
    );
  }
}
