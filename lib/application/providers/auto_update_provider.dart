import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';
import '../services/auto_update_service.dart';

class AutoUpdateProvider extends ChangeNotifier {
  final AutoUpdateService _autoUpdateService;

  final bool _isLoading = false;
  bool _isChecking = false;
  String? _error;
  bool _updateAvailable = false;
  DateTime? _lastCheckDate;

  AutoUpdateProvider({required AutoUpdateService autoUpdateService})
    : _autoUpdateService = autoUpdateService;

  bool get isLoading => _isLoading;
  bool get isChecking => _isChecking;
  String? get error => _error;
  bool get updateAvailable => _updateAvailable;
  DateTime? get lastCheckDate => _lastCheckDate;
  bool get isInitialized => _autoUpdateService.isInitialized;
  String? get feedUrl => _autoUpdateService.feedUrl;

  Future<void> checkForUpdates() async {
    if (!_autoUpdateService.isInitialized) {
      _error = 'Serviço de atualização não inicializado';
      notifyListeners();
      return;
    }

    _isChecking = true;
    _error = null;
    notifyListeners();

    try {
      await _autoUpdateService.checkForUpdatesManually();
      _lastCheckDate = DateTime.now();
      _isChecking = false;
      notifyListeners();
      LoggerService.info('Verificação de atualizações concluída');
    } catch (e) {
      final failure = e is Failure ? e : NetworkFailure(message: e.toString());
      _error = failure.message;
      _isChecking = false;
      notifyListeners();
      LoggerService.error('Erro ao verificar atualizações', e);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void setUpdateAvailable(bool available) {
    _updateAvailable = available;
    notifyListeners();
  }
}
