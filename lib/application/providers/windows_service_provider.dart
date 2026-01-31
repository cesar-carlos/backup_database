import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:flutter/foundation.dart';

class WindowsServiceProvider extends ChangeNotifier {
  WindowsServiceProvider(this._service);
  final IWindowsServiceService _service;

  WindowsServiceStatus? _status;
  bool _isLoading = false;
  String? _error;

  WindowsServiceStatus? get status => _status;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInstalled => _status?.isInstalled ?? false;
  bool get isRunning => _status?.isRunning ?? false;

  Future<void> checkStatus() async {
    _isLoading = true;
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
    _isLoading = true;
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
    _isLoading = true;
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
    _isLoading = true;
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
    if (success) {
      await checkStatus();
    }
    notifyListeners();
    return success;
  }

  Future<bool> stopService() async {
    _isLoading = true;
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
    if (success) {
      await checkStatus();
    }
    notifyListeners();
    return success;
  }
}
