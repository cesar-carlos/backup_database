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
  Future<void>? _initialization;
  bool _minimizeToTray = false;
  bool _closeToTray = false;
  bool trayAvailable = true;
  bool _handlingClose = false;
  Future<void> _windowOperations = Future<void>.value();
  int _generation = 0;
  bool _isShuttingDown = false;
  int _restoreRequests = 0;

  void beginShutdown() {
    _isShuttingDown = true;
    _generation++;
  }

  Future<void> _enqueueWindowOperation(Future<void> Function() action) {
    final generation = _generation;
    final operation = _windowOperations.then((_) async {
      final initializing = _initialization;
      if (initializing != null) await initializing;
      if (!_isShuttingDown && generation == _generation) await action();
    });
    // A failed native operation must not poison subsequent requests.
    _windowOperations = operation.catchError((Object _) {});
    return operation;
  }

  bool get isInitialized => _isInitialized;
  bool get isShuttingDown => _isShuttingDown;

  Future<void> handleTrayUnavailable() async {
    trayAvailable = false;
    // The user may have hidden the window while the tray was initializing,
    // even when the original launch was not minimized.
    if (_isInitialized) await show();
  }

  Future<void> initialize({
    ui.Size size = AppBreakpoints.initialWindow,
    ui.Size minimumSize = AppBreakpoints.minimumWindow,
    bool center = true,
    String title = 'Backup Database',
    bool startMinimized = false,
  }) {
    if (_isInitialized) return Future<void>.value();
    return _initialization ??= _initialize(
      size: size,
      minimumSize: minimumSize,
      center: center,
      title: title,
      startMinimized: startMinimized,
    ).whenComplete(() => _initialization = null);
  }

  Future<void> _initialize({
    required ui.Size size,
    required ui.Size minimumSize,
    required bool center,
    required String title,
    required bool startMinimized,
  }) async {
    _isShuttingDown = false;
    final generation = _generation;
    Future<T> checked<T>(Future<T> operation) async {
      final result = await operation;
      if (_isShuttingDown || generation != _generation) {
        throw StateError('Inicialização da janela cancelada');
      }
      return result;
    }

    try {
      await checked(windowManager.ensureInitialized());
      // waitUntilReadyToShow can restore an existing minimized window itself.
      // Intercept X before any plugin operation capable of exposing the window.
      await checked(windowManager.setPreventClose(true));

      final windowOptions = WindowOptions(
        size: size,
        minimumSize: minimumSize,
        center: center,
        // Keep the native frame composition. A transparent background invokes
        // SetWindowCompositionAttribute on Windows and can hide the native
        // caption on Windows 10. Backdrop effects are managed separately by
        // WindowsNativeChromeBootstrap.
        skipTaskbar: startMinimized, // Ocultar da taskbar se iniciar minimizado
        titleBarStyle: TitleBarStyle.normal,
        windowButtonVisibility: true,
        title: title,
      );

      // The plugin callback is void and does not await async work.
      await checked(windowManager.waitUntilReadyToShow(windowOptions));
      windowManager.addListener(this);
      if (startMinimized) {
        await checked(windowManager.hide());
        LoggerService.info('Aplicativo iniciado minimizado (oculto)');
      } else {
        await checked(windowManager.show());
        await checked(windowManager.focus());
      }

      // Garantir que a janela permaneça oculta se startMinimized for true
      if (startMinimized) {
        // Aguardar um pouco para garantir que a janela foi processada
        await checked(Future<void>.delayed(const Duration(milliseconds: 200)));
        final isVisible = await checked(windowManager.isVisible());
        if (isVisible) {
          LoggerService.warning(
            'Janela ainda visível após hide(), tentando ocultar novamente...',
          );
          await checked(windowManager.hide());
          await checked(windowManager.setSkipTaskbar(true));
        }
        LoggerService.info('Aplicativo iniciado minimizado - janela oculta');
      } else {
        // Garantir que skipTaskbar seja false quando não iniciar minimizado
        await checked(windowManager.setSkipTaskbar(false));
      }

      await checked(windowManager.setMinimumSize(minimumSize));
      _isInitialized = true;

      LoggerService.info(
        'WindowManager inicializado - Tamanho mínimo: '
        '${minimumSize.width}x${minimumSize.height}, '
        'MinimizeToTray: $_minimizeToTray, CloseToTray: $_closeToTray',
      );
    } on Object {
      windowManager.removeListener(this);
      rethrow;
    }
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

  Future<void> show({Duration nativeTimeout = const Duration(seconds: 2)}) {
    // Native restore/show can emit minimize notifications. Those events must
    // not enqueue a hide that runs immediately after a successful restoration.
    _restoreRequests++;
    return _enqueueWindowOperation(() => _show(nativeTimeout))
        .whenComplete(() => _restoreRequests--);
  }

  Future<void> _show(Duration nativeTimeout) async {
    final generation = _generation;
    try {
      LoggerService.info('🪟 Tentando mostrar janela...');

      // Garantir que a janela apareça na taskbar
      await windowManager.setSkipTaskbar(false).timeout(nativeTimeout);
      await Future.delayed(const Duration(milliseconds: 100));
      if (_isShuttingDown || generation != _generation) return;

      // Verificar estado atual
      final isMinimized = await windowManager.isMinimized().timeout(
        nativeTimeout,
      );
      final isVisible = await windowManager.isVisible().timeout(nativeTimeout);
      if (_isShuttingDown || generation != _generation) return;

      LoggerService.info(
        '📊 Estado antes de mostrar - Minimizada: $isMinimized, Visível: $isVisible',
      );

      // Se estiver minimizada, restaurar primeiro
      if (isMinimized) {
        LoggerService.info('🔄 Janela está minimizada, restaurando...');
        await windowManager.restore().timeout(nativeTimeout);
        await Future.delayed(const Duration(milliseconds: 200));
        if (_isShuttingDown || generation != _generation) return;
      }

      // SEMPRE chamar show() mesmo que já esteja visível
      // Isso é crítico quando a janela foi ocultada com hide()
      LoggerService.info('👁️ Chamando show()...');
      await windowManager.show().timeout(nativeTimeout);
      await Future.delayed(const Duration(milliseconds: 200));
      if (_isShuttingDown || generation != _generation) return;

      // Verificar se realmente está visível agora
      final isVisibleAfterShow = await windowManager.isVisible().timeout(
        nativeTimeout,
      );
      if (_isShuttingDown || generation != _generation) return;
      LoggerService.info('📊 Visível após show(): $isVisibleAfterShow');

      if (!isVisibleAfterShow) {
        // Se ainda não estiver visível, tentar restaurar novamente
        LoggerService.warning(
          '⚠️ Janela ainda não está visível após show(), tentando restaurar...',
        );
        await windowManager.restore().timeout(nativeTimeout);
        await Future.delayed(const Duration(milliseconds: 200));
        if (_isShuttingDown || generation != _generation) return;
        await windowManager.show().timeout(nativeTimeout);
        await Future.delayed(const Duration(milliseconds: 200));
        if (_isShuttingDown || generation != _generation) return;
      }

      // Focar a janela
      LoggerService.info('🎯 Focando janela...');
      await windowManager.focus().timeout(nativeTimeout);
      await Future.delayed(const Duration(milliseconds: 100));
      if (_isShuttingDown || generation != _generation) return;

      // Verificação final
      final finalIsVisible = await windowManager.isVisible().timeout(
        nativeTimeout,
      );
      final finalIsMinimized = await windowManager.isMinimized().timeout(
        nativeTimeout,
      );
      if (_isShuttingDown || generation != _generation) return;
      LoggerService.info(
        '✅ Janela exibida! Visível: $finalIsVisible, Minimizada: $finalIsMinimized',
      );

      if (!finalIsVisible) {
        LoggerService.error(
          '❌ CRÍTICO: Janela ainda não está visível após todas as tentativas!',
        );
        // Última tentativa
        await windowManager.restore().timeout(nativeTimeout);
        await Future.delayed(const Duration(milliseconds: 300));
        if (_isShuttingDown || generation != _generation) return;
        await windowManager.show().timeout(nativeTimeout);
        if (_isShuttingDown || generation != _generation) return;
        await windowManager.focus().timeout(nativeTimeout);
      }
      await _markIpcShowIfWindowIsVisible(generation, nativeTimeout);
    } on Object catch (e, stackTrace) {
      if (_isShuttingDown || generation != _generation) return;
      LoggerService.error('❌ Erro ao mostrar janela', e, stackTrace);
      // Tentar método alternativo
      try {
        LoggerService.info('🔄 Tentando método alternativo...');
        await windowManager.setSkipTaskbar(false).timeout(nativeTimeout);
        if (_isShuttingDown || generation != _generation) return;
        await windowManager.restore().timeout(nativeTimeout);
        await Future.delayed(const Duration(milliseconds: 200));
        if (_isShuttingDown || generation != _generation) return;
        await windowManager.show().timeout(nativeTimeout);
        if (_isShuttingDown || generation != _generation) return;
        await windowManager.focus().timeout(nativeTimeout);
        await _markIpcShowIfWindowIsVisible(generation, nativeTimeout);
      } on Object catch (e2) {
        LoggerService.error('❌ Erro crítico ao mostrar janela', e2);
        rethrow;
      }
    }
  }

  Future<void> _markIpcShowIfWindowIsVisible(
    int generation,
    Duration nativeTimeout,
  ) async {
    if (_isShuttingDown || generation != _generation) return;
    final isVisible = await windowManager.isVisible().timeout(nativeTimeout);
    final isMinimized = await windowManager.isMinimized().timeout(
      nativeTimeout,
    );
    if (_isShuttingDown || generation != _generation) return;
    if (isVisible && !isMinimized) {
      IpcShowWindowConfirmation.markShown();
      return;
    }
    throw StateError('A janela não ficou visível após a restauração');
  }

  Future<void> restore() => show();

  Future<void> hide() => _enqueueWindowOperation(windowManager.hide);

  Future<void> minimize() => _enqueueWindowOperation(windowManager.minimize);

  Future<void> maximize() => _enqueueWindowOperation(() async {
    final generation = _generation;
    final maximized = await windowManager.isMaximized();
    if (_isShuttingDown || generation != _generation) return;
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  });

  Future<void> close() => _enqueueWindowOperation(windowManager.close);

  Future<void> setTitle(String title) =>
      _enqueueWindowOperation(() => windowManager.setTitle(title));

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
    if (_minimizeToTray && trayAvailable && _restoreRequests == 0) {
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
    if (_isShuttingDown || _handlingClose || WindowCloseGuard.isBlocked) return;
    _handlingClose = true;
    try {
      await _handleWindowClose();
    } finally {
      _handlingClose = false;
    }
  }

  Future<void> _hideToTray() => _enqueueWindowOperation(() async {
    // Availability can change while a restoration ahead of us is running.
    if (!trayAvailable) return;
    final generation = _generation;
    await windowManager.hide();
    if (_isShuttingDown || generation != _generation) return;
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
