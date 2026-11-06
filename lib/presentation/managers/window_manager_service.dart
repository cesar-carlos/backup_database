import 'dart:async';
import 'dart:ui' as ui;

import 'package:backup_database/core/theme/tokens/app_breakpoints.dart';
import 'package:backup_database/core/utils/ipc_show_window_confirmation.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/window_close_guard.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagerService with WindowListener {
  factory WindowManagerService() => _instance;
  WindowManagerService._();
  static final WindowManagerService _instance = WindowManagerService._();

  VoidCallback? _onMinimize;
  FutureOr<void> Function()? _onClose;
  VoidCallback? _onFocus;

  bool _isInitialized = false;
  bool _minimizeToTray = false;
  bool _closeToTray = false;
  bool trayAvailable = true;
  bool _handlingClose = false;
  Future<void> _windowOperations = Future<void>.value();
  int _generation = 0;
  bool _isShuttingDown = false;

  void beginShutdown() {
    _isShuttingDown = true;
    _generation++;
  }

  Future<void> _enqueueWindowOperation(Future<void> Function() action) {
    final generation = _generation;
    final operation = _windowOperations.then((_) async {
      if (!_isShuttingDown && generation == _generation) await action();
    });
    // A failed native operation must not poison subsequent requests.
    _windowOperations = operation.catchError((Object _) {});
    return operation;
  }

  bool get isInitialized => _isInitialized;

  Future<void> initialize({
    ui.Size size = AppBreakpoints.initialWindow,
    ui.Size minimumSize = AppBreakpoints.minimumWindow,
    bool center = true,
    String title = 'Backup Database',
    bool startMinimized = false,
  }) async {
    if (_isInitialized) return;
    _isShuttingDown = false;

    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      size: size,
      minimumSize: minimumSize,
      center: center,
      backgroundColor: Colors.transparent,
      skipTaskbar: startMinimized, // Ocultar da taskbar se iniciar minimizado
      titleBarStyle: TitleBarStyle.normal,
      title: title,
    );

    // The plugin callback is void and does not await async work.
    await windowManager.waitUntilReadyToShow(windowOptions);
    // O X decide no WM_CLOSE. preventClose tem de valer antes do show.
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    if (startMinimized) {
      await windowManager.hide();
      LoggerService.info('Aplicativo iniciado minimizado (oculto)');
    } else {
      await windowManager.show();
      await windowManager.focus();
    }

    // Garantir que a janela permaneça oculta se startMinimized for true
    if (startMinimized) {
      // Aguardar um pouco para garantir que a janela foi processada
      await Future.delayed(const Duration(milliseconds: 200));
      final isVisible = await windowManager.isVisible();
      if (isVisible) {
        LoggerService.warning(
          'Janela ainda visível após hide(), tentando ocultar novamente...',
        );
        await windowManager.hide();
        await windowManager.setSkipTaskbar(true);
      }
      LoggerService.info('Aplicativo iniciado minimizado - janela oculta');
    } else {
      // Garantir que skipTaskbar seja false quando não iniciar minimizado
      await windowManager.setSkipTaskbar(false);
    }

    await windowManager.setMinimumSize(minimumSize);
    _isInitialized = true;

    LoggerService.info(
      'WindowManager inicializado - Tamanho mínimo: '
      '${minimumSize.width}x${minimumSize.height}, '
      'MinimizeToTray: $_minimizeToTray, CloseToTray: $_closeToTray',
    );
  }

  void prepareTrayCloseBehavior({
    required bool minimizeToTray,
    required bool closeToTray,
  }) {
    _minimizeToTray = minimizeToTray;
    _closeToTray = closeToTray;
  }

  void setCallbacks({
    VoidCallback? onMinimize,
    FutureOr<void> Function()? onClose,
    VoidCallback? onFocus,
  }) {
    _onMinimize = onMinimize;
    _onClose = onClose;
    _onFocus = onFocus;
  }

  bool get _keepsProcessOnClose =>
      trayAvailable &&
      keepsProcessWhenWindowCloses(
        minimizeToTray: _minimizeToTray,
        closeToTray: _closeToTray,
      );

  Future<void> setMinimizeToTray(bool value) async {
    _minimizeToTray = value;
    LoggerService.debug('Minimizar para bandeja: $value');
  }

  Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
    LoggerService.debug('Fechar para bandeja: $value');
  }

  Future<void> show() => _enqueueWindowOperation(_show);

  Future<void> _show() async {
    try {
      LoggerService.info('🪟 Tentando mostrar janela...');

      // Garantir que a janela apareça na taskbar
      await windowManager.setSkipTaskbar(false);
      await Future.delayed(const Duration(milliseconds: 100));
      if (_isShuttingDown) return;

      // Verificar estado atual
      final isMinimized = await windowManager.isMinimized();
      final isVisible = await windowManager.isVisible();

      LoggerService.info(
        '📊 Estado antes de mostrar - Minimizada: $isMinimized, Visível: $isVisible',
      );

      // Se estiver minimizada, restaurar primeiro
      if (isMinimized) {
        LoggerService.info('🔄 Janela está minimizada, restaurando...');
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        if (_isShuttingDown) return;
      }

      // SEMPRE chamar show() mesmo que já esteja visível
      // Isso é crítico quando a janela foi ocultada com hide()
      LoggerService.info('👁️ Chamando show()...');
      await windowManager.show();
      await Future.delayed(const Duration(milliseconds: 200));
      if (_isShuttingDown) return;

      // Verificar se realmente está visível agora
      final isVisibleAfterShow = await windowManager.isVisible();
      LoggerService.info('📊 Visível após show(): $isVisibleAfterShow');

      if (!isVisibleAfterShow) {
        // Se ainda não estiver visível, tentar restaurar novamente
        LoggerService.warning(
          '⚠️ Janela ainda não está visível após show(), tentando restaurar...',
        );
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        if (_isShuttingDown) return;
        await windowManager.show();
        await Future.delayed(const Duration(milliseconds: 200));
        if (_isShuttingDown) return;
      }

      // Focar a janela
      LoggerService.info('🎯 Focando janela...');
      await windowManager.focus();
      await Future.delayed(const Duration(milliseconds: 100));
      if (_isShuttingDown) return;

      // Verificação final
      final finalIsVisible = await windowManager.isVisible();
      final finalIsMinimized = await windowManager.isMinimized();
      LoggerService.info(
        '✅ Janela exibida! Visível: $finalIsVisible, Minimizada: $finalIsMinimized',
      );

      if (!finalIsVisible) {
        LoggerService.error(
          '❌ CRÍTICO: Janela ainda não está visível após todas as tentativas!',
        );
        // Última tentativa
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 300));
        if (_isShuttingDown) return;
        await windowManager.show();
        await windowManager.focus();
      }
      await _markIpcShowIfWindowIsVisible();
    } on Object catch (e, stackTrace) {
      if (_isShuttingDown) return;
      LoggerService.error('❌ Erro ao mostrar janela', e, stackTrace);
      // Tentar método alternativo
      try {
        LoggerService.info('🔄 Tentando método alternativo...');
        await windowManager.setSkipTaskbar(false);
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        if (_isShuttingDown) return;
        await windowManager.show();
        await windowManager.focus();
        await _markIpcShowIfWindowIsVisible();
      } on Object catch (e2) {
        LoggerService.error('❌ Erro crítico ao mostrar janela', e2);
        rethrow;
      }
    }
  }

  Future<void> _markIpcShowIfWindowIsVisible() async {
    if (_isShuttingDown) return;
    final isVisible = await windowManager.isVisible();
    final isMinimized = await windowManager.isMinimized();
    if (isVisible && !isMinimized) {
      IpcShowWindowConfirmation.markShown();
      return;
    }
    throw StateError('A janela não ficou visível após a restauração');
  }

  Future<void> restore() => show();

  Future<void> hide() => _enqueueWindowOperation(windowManager.hide);

  Future<void> minimize() async {
    await windowManager.minimize();
  }

  Future<void> maximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> close() async {
    await windowManager.close();
  }

  Future<void> setTitle(String title) async {
    await windowManager.setTitle(title);
  }

  Future<bool> isVisible() async {
    return windowManager.isVisible();
  }

  Future<bool> isMinimized() async {
    return windowManager.isMinimized();
  }

  Future<bool> isFocused() async {
    return windowManager.isFocused();
  }

  // WindowListener callbacks
  @override
  void onWindowMinimize() {
    if (_minimizeToTray && trayAvailable) {
      unawaited(
        _hideToTray().catchError((e) {
          LoggerService.error('Erro ao ocultar janela ao minimizar', e);
        }),
      );
    }
    _onMinimize?.call();
  }

  @override
  Future<void> onWindowClose() async {
    if (_handlingClose || WindowCloseGuard.isBlocked) return;
    _handlingClose = true;
    try {
      await _handleWindowClose();
    } finally {
      _handlingClose = false;
    }
  }

  Future<void> _hideToTray() => _enqueueWindowOperation(() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  });

  Future<void> _handleWindowClose() async {
    LoggerService.info(
      'Tentativa de fechar janela - minimizeToTray: $_minimizeToTray, '
      'closeToTray: $_closeToTray',
    );

    if (_keepsProcessOnClose) {
      try {
        await _hideToTray();
        LoggerService.info('Janela ocultada para a bandeja');
      } on Object catch (e, stackTrace) {
        LoggerService.error(
          'Erro ao ocultar janela para bandeja',
          e,
          stackTrace,
        );
      }
      return;
    }

    try {
      LoggerService.info('Fechamento permitido - encerrando aplicativo');
      final onClose = _onClose;
      if (onClose != null) {
        await onClose();
      } else {
        LoggerService.warning(
          'Fechamento aguardando configuração do aplicativo',
        );
      }
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao encerrar aplicativo',
        e,
        stackTrace,
      );
    }
  }

  @override
  void onWindowFocus() {
    _onFocus?.call();
  }

  @override
  void onWindowBlur() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowEvent(String eventName) {}

  void dispose() {
    _generation++;
    windowManager.removeListener(this);
    _isInitialized = false;
    _onMinimize = null;
    _onClose = null;
    _onFocus = null;
    _minimizeToTray = false;
    _closeToTray = false;
    trayAvailable = true;
  }
}

/// O X encerra o processo só quando as duas opções da bandeja estão desligadas.
/// "Minimizar para bandeja" também mantém o processo, conforme a preferência
/// apresentada na tela de configurações. A interceptação nativa fica ativa
/// independentemente destas opções para permitir a limpeza antes de sair.
bool keepsProcessWhenWindowCloses({
  required bool minimizeToTray,
  required bool closeToTray,
}) {
  return minimizeToTray || closeToTray;
}
