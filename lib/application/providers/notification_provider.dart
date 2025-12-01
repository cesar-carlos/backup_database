import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/email_config.dart';
import '../../domain/repositories/i_email_config_repository.dart';
import '../services/notification_service.dart';

class NotificationProvider extends ChangeNotifier {
  final IEmailConfigRepository _emailConfigRepository;
  final NotificationService _notificationService;

  EmailConfig? _emailConfig;
  bool _isLoading = false;
  String? _error;
  bool _isTesting = false;

  NotificationProvider({
    required IEmailConfigRepository emailConfigRepository,
    required NotificationService notificationService,
  })  : _emailConfigRepository = emailConfigRepository,
        _notificationService = notificationService {
    loadConfig();
  }

  EmailConfig? get emailConfig => _emailConfig;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTesting => _isTesting;
  bool get isConfigured => _emailConfig != null && _emailConfig!.enabled;

  Future<void> loadConfig() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _emailConfigRepository.get();
      result.fold(
        (config) {
          _emailConfig = config;
          _error = null;
        },
        (failure) {
          final f = failure as Failure;
          // Se não encontrou configuração, não é um erro - apenas não há dados salvos
          if (f is NotFoundFailure) {
            _emailConfig = null;
            _error = null;
          } else {
            _emailConfig = null;
            _error = f.message;
          }
        },
      );
    } catch (e) {
      _emailConfig = null;
      _error = 'Erro ao carregar configuração de e-mail: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveConfig(EmailConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _emailConfigRepository.save(config);
      return result.fold(
        (savedConfig) {
          _emailConfig = savedConfig;
          _error = null;
          _isLoading = false;
          notifyListeners();
          return true;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isLoading = false;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = 'Erro ao salvar configuração: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> testConfiguration() async {
    if (_emailConfig == null) {
      _error = 'Nenhuma configuração de e-mail definida';
      notifyListeners();
      return false;
    }

    _isTesting = true;
    _error = null;
    notifyListeners();

    try {
      final result =
          await _notificationService.testEmailConfiguration(_emailConfig!);
      return result.fold(
        (success) {
          _error = null;
          _isTesting = false;
          notifyListeners();
          return success;
        },
        (failure) {
          final f = failure as Failure;
          _error = f.message;
          _isTesting = false;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = 'Erro ao testar configuração: $e';
      _isTesting = false;
      notifyListeners();
      return false;
    }
  }

  void toggleEnabled(bool enabled) {
    if (_emailConfig != null) {
      _emailConfig = _emailConfig!.copyWith(enabled: enabled);
      saveConfig(_emailConfig!);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

