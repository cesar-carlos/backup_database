import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:flutter/foundation.dart';

class WindowsServiceProvider extends ChangeNotifier {
  WindowsServiceProvider(this._service);
  final IWindowsServiceService _service;

  WindowsServiceStatus? _status;
  bool _isLoading = false;
  bool _isStarting = false;
  String? _error;

  WindowsServiceStatus? get status => _status;
  bool get isLoading => _isLoading;
  bool get isStarting => _isStarting;
  String? get error => _error;
  bool get isInstalled => _status?.isInstalled ?? false;
  bool get isRunning => _status?.isRunning ?? false;

  Future<void> checkStatus() async {
    if (_isLoading) return;
    _isLoading = true;
    _isStarting = false;
    _error = null;
    notifyListeners();

    final result = await _service.getStatus();

    result.fold(
      (status) {
        _status = status;
        _error = null;
      },
      (failure) {
        _error = failure is Failure ? failure.message : failure.toString();
        LoggerService.error('Erro ao verificar status do serviço', failure);
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> installService({String? user, String? password}) async {
    if (_isLoading) return false;
    _isLoading = true;
    _isStarting = false;
    _error = null;
    notifyListeners();

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

    _isLoading = false;
    if (success) {
      await checkStatus();
    }
    notifyListeners();
    return success;
  }

  Future<bool> uninstallService() async {
    if (_isLoading) return false;
    _isLoading = true;
    _isStarting = false;
    _error = null;
    notifyListeners();

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

    _isLoading = false;
    if (success) {
      await checkStatus();
    }
    notifyListeners();
    return success;
  }

  Future<bool> startService() async {
    if (_isLoading) return false;
    _isLoading = true;
    _isStarting = true;
    _error = null;
    notifyListeners();

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

    _isLoading = false;
    _isStarting = false;
    await _refreshStatusSilently();
    notifyListeners();
    return success;
  }

  Future<bool> stopService() async {
    if (_isLoading) return false;
    _isLoading = true;
    _isStarting = false;
    _error = null;
    notifyListeners();

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

    _isLoading = false;
    await _refreshStatusSilently();
    notifyListeners();
    return success;
  }

  Future<bool> restartService() async {
    if (_isLoading) return false;
    _isLoading = true;
    _isStarting = true;
    _error = null;
    notifyListeners();

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

    _isLoading = false;
    _isStarting = false;
    await _refreshStatusSilently();
    notifyListeners();
    return success;
  }

  Future<void> _refreshStatusSilently() async {
    final result = await _service.getStatus();
    result.fold(
      (status) {
        _status = status;
      },
      (_) {},
    );
  }
}
