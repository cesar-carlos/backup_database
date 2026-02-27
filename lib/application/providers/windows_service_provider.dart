import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
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

class WindowsServiceProvider extends ChangeNotifier {
  WindowsServiceProvider(this._service, this._eventLog);
  final IWindowsServiceService _service;
  final IWindowsServiceEventLogger _eventLog;

  WindowsServiceStatus? _status;
  bool _isLoading = false;
  WindowsServiceOperation _operation = WindowsServiceOperation.none;
  String? _error;

  WindowsServiceStatus? _statusCache;
  DateTime? _statusCacheTimestamp;
  static const _statusCacheTtl = Duration(seconds: 2);

  WindowsServiceStatus? get status => _status;
  bool get isLoading => _isLoading;
  bool get isStarting =>
      _operation == WindowsServiceOperation.start ||
      _operation == WindowsServiceOperation.restart;
  WindowsServiceOperation get operation => _operation;
  String? get error => _error;
  bool get isInstalled => _status?.isInstalled ?? false;
  bool get isRunning => _status?.isRunning ?? false;

  Future<void> checkStatus({bool forceRefresh = false}) async {
    if (_isLoading) return;

    final cacheValid = !forceRefresh &&
        _statusCache != null &&
        _statusCacheTimestamp != null &&
        DateTime.now().difference(_statusCacheTimestamp!) < _statusCacheTtl;

    if (cacheValid) {
      _status = _statusCache;
      _error = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _operation = WindowsServiceOperation.check;
    _error = null;
    notifyListeners();

    final result = await _service.getStatus();

    result.fold(
      (status) {
        _status = status;
        _statusCache = status;
        _statusCacheTimestamp = DateTime.now();
        _error = null;
      },
      (failure) {
        _error = failure is Failure ? failure.message : failure.toString();
        _statusCache = null;
        _statusCacheTimestamp = null;
        LoggerService.error('Erro ao verificar status do serviço', failure);
      },
    );

    _isLoading = false;
    _operation = WindowsServiceOperation.none;
    notifyListeners();
  }

  void _invalidateStatusCache() {
    _statusCache = null;
    _statusCacheTimestamp = null;
  }

  Future<bool> installService({String? user, String? password}) async {
    if (_isLoading) return false;
    _isLoading = true;
    _operation = WindowsServiceOperation.install;
    _error = null;
    notifyListeners();

    await _eventLog.logInstallStarted();

    final result = await _service.installService(
      serviceUser: user,
      servicePassword: password,
    );

    final success = result.fold(
      (_) {
        _error = null;
        return true;
      },
      (failure) {
        _error = failure is Failure ? failure.message : failure.toString();
        LoggerService.error('Erro ao instalar serviço', failure);
        return false;
      },
    );

    if (success) {
      await _eventLog.logInstallSucceeded();
    } else {
      await _eventLog.logInstallFailed(error: _error ?? 'Erro desconhecido');
    }

    _isLoading = false;
    _operation = WindowsServiceOperation.none;
    if (success) {
      _invalidateStatusCache();
      await checkStatus(forceRefresh: true);
    }
    notifyListeners();
    return success;
  }

  Future<bool> uninstallService() async {
    if (_isLoading) return false;
    _isLoading = true;
    _operation = WindowsServiceOperation.uninstall;
    _error = null;
    notifyListeners();

    await _eventLog.logUninstallStarted();

    final result = await _service.uninstallService();

    final success = result.fold(
      (_) {
        _error = null;
        return true;
      },
      (failure) {
        _error = failure is Failure ? failure.message : failure.toString();
        LoggerService.error('Erro ao remover serviço', failure);
        return false;
      },
    );

    if (success) {
      await _eventLog.logUninstallSucceeded();
    } else {
      await _eventLog.logUninstallFailed(error: _error ?? 'Erro desconhecido');
    }

    _isLoading = false;
    _operation = WindowsServiceOperation.none;
    if (success) {
      _invalidateStatusCache();
      await checkStatus(forceRefresh: true);
    }
    notifyListeners();
    return success;
  }

  Future<bool> startService() async {
    if (_isLoading) return false;
    _isLoading = true;
    _operation = WindowsServiceOperation.start;
    _error = null;
    notifyListeners();

    await _eventLog.logStartStarted();

    final result = await _service.startService();

    final success = result.fold(
      (_) {
        _error = null;
        return true;
      },
      (failure) {
        _error = failure is Failure ? failure.message : failure.toString();
        LoggerService.error('Erro ao iniciar serviço', failure);
        return false;
      },
    );

    if (success) {
      await _eventLog.logStartSucceeded();
    } else {
      final err = _error ?? '';
      if (_isTimeoutMessage(err)) {
        await _eventLog.logStartTimeout(
          timeout: const Duration(seconds: 60),
        );
      } else {
        await _eventLog.logStartFailed(error: err);
      }
    }

    _isLoading = false;
    _operation = WindowsServiceOperation.none;
    _invalidateStatusCache();
    await _refreshStatusSilently();
    notifyListeners();
    return success;
  }

  static bool _isTimeoutMessage(String msg) =>
      msg.toLowerCase().contains('timeout') ||
      msg.toLowerCase().contains('tempo esgotado');

  Future<bool> stopService() async {
    if (_isLoading) return false;
    _isLoading = true;
    _operation = WindowsServiceOperation.stop;
    _error = null;
    notifyListeners();

    await _eventLog.logStopStarted();

    final result = await _service.stopService();

    final success = result.fold(
      (_) {
        _error = null;
        return true;
      },
      (failure) {
        _error = failure is Failure ? failure.message : failure.toString();
        LoggerService.error('Erro ao parar serviço', failure);
        return false;
      },
    );

    if (success) {
      await _eventLog.logStopSucceeded();
    } else {
      final err = _error ?? '';
      if (_isTimeoutMessage(err)) {
        await _eventLog.logStopTimeout(
          timeout: const Duration(seconds: 60),
        );
      } else {
        await _eventLog.logStopFailed(error: err);
      }
    }

    _isLoading = false;
    _operation = WindowsServiceOperation.none;
    _invalidateStatusCache();
    await _refreshStatusSilently();
    notifyListeners();
    return success;
  }

  Future<bool> restartService() async {
    if (_isLoading) return false;
    _isLoading = true;
    _operation = WindowsServiceOperation.restart;
    _error = null;
    notifyListeners();

    await _eventLog.logStopStarted();
    await _eventLog.logStartStarted();

    final result = await _service.restartService();

    final success = result.fold(
      (_) {
        _error = null;
        return true;
      },
      (failure) {
        _error = failure is Failure ? failure.message : failure.toString();
        LoggerService.error('Erro ao reiniciar serviço', failure);
        return false;
      },
    );

    if (success) {
      await _eventLog.logStopSucceeded();
      await _eventLog.logStartSucceeded();
    } else {
      final err = _error ?? '';
      if (_isTimeoutMessage(err)) {
        await _eventLog.logStartTimeout(
          timeout: const Duration(seconds: 60),
        );
      } else {
        await _eventLog.logStartFailed(error: err);
      }
    }

    _isLoading = false;
    _operation = WindowsServiceOperation.none;
    _invalidateStatusCache();
    await _refreshStatusSilently();
    notifyListeners();
    return success;
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
