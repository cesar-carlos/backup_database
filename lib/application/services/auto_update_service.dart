import 'dart:async';

import 'package:auto_updater/auto_updater.dart';

import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';

class AutoUpdateService {
  Timer? _checkTimer;
  bool _isInitialized = false;
  String? _feedUrl;
  static const int _defaultCheckInterval = 3600;

  Future<void> initialize(String? feedUrl) async {
    if (_isInitialized) {
      LoggerService.warning('AutoUpdateService já foi inicializado');
      return;
    }

    if (feedUrl == null || feedUrl.isEmpty) {
      LoggerService.warning(
        'AUTO_UPDATE_FEED_URL não configurada. Atualizações automáticas desabilitadas.',
      );
      return;
    }

    try {
      _feedUrl = feedUrl;
      await AutoUpdater.instance.setFeedURL(feedUrl);
      LoggerService.info(
        'AutoUpdateService inicializado com feed URL: $feedUrl',
      );

      // Configurar intervalo de verificação automática
      await AutoUpdater.instance.setScheduledCheckInterval(
        _defaultCheckInterval,
      );

      LoggerService.info(
        'Atualização automática configurada (verificação a cada ${_defaultCheckInterval}s)',
      );
      LoggerService.info(
        'IMPORTANTE: Instalador executará em modo /VERYSILENT para atualizações forçadas',
      );

      _isInitialized = true;

      await _checkForUpdates();
      _startPeriodicCheck();
    } catch (e) {
      LoggerService.error('Erro ao inicializar AutoUpdateService', e);
    }
  }

  void _startPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(
      Duration(seconds: _defaultCheckInterval),
      (_) => _checkForUpdates(),
    );
    LoggerService.info('Verificação periódica de atualizações iniciada');
  }

  Future<void> _checkForUpdates() async {
    if (!_isInitialized) {
      LoggerService.warning(
        'AutoUpdateService não inicializado. Não é possível verificar atualizações.',
      );
      return;
    }

    try {
      LoggerService.info('Verificando atualizações...');
      await AutoUpdater.instance.checkForUpdates();
    } catch (e) {
      LoggerService.warning('Erro ao verificar atualizações: $e');
    }
  }

  Future<void> checkForUpdatesManually() async {
    if (!_isInitialized) {
      throw ValidationFailure(message: 'AutoUpdateService não inicializado');
    }

    try {
      LoggerService.info('Verificação manual de atualizações solicitada');
      await AutoUpdater.instance.checkForUpdates();
    } catch (e) {
      LoggerService.error('Erro ao verificar atualizações manualmente', e);
      throw NetworkFailure(
        message: 'Erro ao verificar atualizações: ${e.toString()}',
        originalError: e,
      );
    }
  }

  void dispose() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isInitialized = false;
    LoggerService.info('AutoUpdateService finalizado');
  }

  bool get isInitialized => _isInitialized;
  String? get feedUrl => _feedUrl;
}
