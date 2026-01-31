import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';

class AutoUpdateService with UpdaterListener {
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
        'AUTO_UPDATE_FEED_URL não configurada. '
        'Atualizações automáticas desabilitadas.',
      );
      return;
    }

    try {
      _feedUrl = feedUrl;

      AutoUpdater.instance.addListener(this);
      LoggerService.info(
        'UpdaterListener registrado para eventos de atualização',
      );

      await AutoUpdater.instance.setFeedURL(feedUrl);
      LoggerService.info(
        'AutoUpdateService inicializado com feed URL: '
        '$feedUrl',
      );

      await AutoUpdater.instance.setScheduledCheckInterval(
        _defaultCheckInterval,
      );

      LoggerService.info(
        'Atualização automática configurada (verificação a cada '
        '${_defaultCheckInterval}s)',
      );

      _isInitialized = true;

      LoggerService.info(
        'WinSparkle configurado para verificações automáticas '
        'em background',
      );
    } on Object catch (e) {
      LoggerService.error('Erro ao inicializar AutoUpdateService', e);
    }
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    LoggerService.error(
      'AutoUpdate ERROR: ${error?.message ?? "Erro desconhecido"}',
    );
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    LoggerService.info('AutoUpdate: Verificando atualizações...');
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    LoggerService.info(
      'AutoUpdate: Nova versão disponível! '
      'Versão: ${appcastItem?.versionString ?? "desconhecida"}',
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    LoggerService.info('AutoUpdate: Nenhuma atualização disponível');
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    LoggerService.info(
      'AutoUpdate: Download concluído! '
      'Versão: ${appcastItem?.versionString ?? "desconhecida"}',
    );
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    LoggerService.info(
      '============================================================',
    );
    LoggerService.info(
      'AutoUpdate: FECHANDO APLICATIVO PARA INSTALAR ATUALIZAÇÃO!',
    );
    LoggerService.info(
      'Nova versão: ${appcastItem?.versionString ?? "desconhecida"}',
    );
    LoggerService.info(
      '============================================================',
    );

    dispose();

    Future.delayed(const Duration(milliseconds: 500), () {
      LoggerService.info('AutoUpdate: Encerrando processo...');
      exit(0);
    });
  }

  Future<void> checkForUpdatesManually() async {
    if (!_isInitialized) {
      throw const ValidationFailure(
        message: 'AutoUpdateService não inicializado',
      );
    }

    try {
      LoggerService.info('Verificação manual de atualizações solicitada');
      await AutoUpdater.instance.checkForUpdates();
    } on Object catch (e) {
      LoggerService.error('Erro ao verificar atualizações manualmente', e);
      throw NetworkFailure(
        message: 'Erro ao verificar atualizações: $e',
        originalError: e,
      );
    }
  }

  void dispose() {
    if (_isInitialized) {
      try {
        AutoUpdater.instance.removeListener(this);
      } on Object catch (e, s) {
        LoggerService.warning('Erro ao remover listener do AutoUpdater', e, s);
      }
    }

    _isInitialized = false;
    LoggerService.info('AutoUpdateService finalizado');
  }

  bool get isInitialized => _isInitialized;
  String? get feedUrl => _feedUrl;
}
