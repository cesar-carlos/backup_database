import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';

import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';

class AutoUpdateService with UpdaterListener {
  bool _isInitialized = false;
  String? _feedUrl;
  
  // Intervalo de verificação automática em segundos (1 hora)
  // O WinSparkle usa esse intervalo para fazer verificações em background
  // que não mostram diálogo a menos que haja uma atualização disponível
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
      
      // CRÍTICO: Registrar listener ANTES de configurar o feed URL
      // para capturar todos os eventos do WinSparkle
      AutoUpdater.instance.addListener(this);
      LoggerService.info('UpdaterListener registrado para eventos de atualização');
      
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

      _isInitialized = true;

      // NÃO fazer verificação no startup para evitar mostrar diálogo desnecessário
      // O WinSparkle fará verificações automáticas em background
      // e só mostrará diálogo se realmente houver uma atualização disponível
      LoggerService.info(
        'WinSparkle configurado para verificações automáticas em background',
      );
    } catch (e) {
      LoggerService.error('Erro ao inicializar AutoUpdateService', e);
    }
  }
  
  // ============================================================
  // IMPLEMENTAÇÃO DO UpdaterListener - CRÍTICO PARA AUTO-UPDATE
  // ============================================================
  
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
    // ============================================================
    // CRÍTICO: Este é o callback que o WinSparkle chama quando
    // precisa que o aplicativo feche para executar o instalador!
    // 
    // Se o app não fechar aqui, o instalador NÃO será executado!
    // ============================================================
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
    
    // Limpar recursos antes de fechar
    dispose();
    
    // FECHAR O APLICATIVO IMEDIATAMENTE para permitir a instalação
    // O WinSparkle está esperando o app fechar para executar o instalador
    Future.delayed(const Duration(milliseconds: 500), () {
      LoggerService.info('AutoUpdate: Encerrando processo...');
      exit(0);
    });
  }

  // Removido _startPeriodicCheck() e _checkForUpdates()
  // O WinSparkle já faz verificações automáticas em background
  // usando o intervalo configurado em setScheduledCheckInterval
  // Essas verificações não mostram diálogo a menos que haja uma atualização disponível

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
    // Remover listener ao finalizar
    if (_isInitialized) {
      try {
        AutoUpdater.instance.removeListener(this);
      } catch (_) {}
    }
    
    _isInitialized = false;
    LoggerService.info('AutoUpdateService finalizado');
  }

  bool get isInitialized => _isInitialized;
  String? get feedUrl => _feedUrl;
}
