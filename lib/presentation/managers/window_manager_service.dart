import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/utils/logger_service.dart';

class WindowManagerService with WindowListener {
  static final WindowManagerService _instance = WindowManagerService._();
  factory WindowManagerService() => _instance;
  WindowManagerService._();

  VoidCallback? _onMinimize;
  VoidCallback? _onClose;
  VoidCallback? _onFocus;

  bool _isInitialized = false;
  bool _minimizeToTray = true;
  bool _closeToTray = true;

  Future<void> initialize({
    ui.Size size = const ui.Size(1280, 800),
    ui.Size minimumSize = const ui.Size(900, 650),
    bool center = true,
    String title = 'Backup Database',
    bool startMinimized = false,
  }) async {
    if (_isInitialized) return;

    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      size: size,
      minimumSize: minimumSize,
      center: center,
      backgroundColor: Colors.transparent,
      skipTaskbar: false, // IMPORTANTE: sempre false para aparecer na taskbar
      titleBarStyle: TitleBarStyle.normal,
      title: title,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startMinimized) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });

    // Garantir que o tamanho mínimo seja aplicado após a inicialização
    await windowManager.setMinimumSize(minimumSize);

    windowManager.addListener(this);
    _isInitialized = true;

    LoggerService.info(
      'WindowManager inicializado - Tamanho mínimo: ${minimumSize.width}x${minimumSize.height}',
    );
  }

  void setCallbacks({
    VoidCallback? onMinimize,
    VoidCallback? onClose,
    VoidCallback? onFocus,
  }) {
    _onMinimize = onMinimize;
    _onClose = onClose;
    _onFocus = onFocus;
  }

  void setMinimizeToTray(bool value) {
    _minimizeToTray = value;
    LoggerService.debug('Minimizar para bandeja: $value');
  }

  void setCloseToTray(bool value) {
    _closeToTray = value;
    LoggerService.debug('Fechar para bandeja: $value');
  }

  Future<void> show() async {
    try {
      LoggerService.info('🪟 Tentando mostrar janela...');

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
      }

      // SEMPRE chamar show() mesmo que já esteja visível
      // Isso é crítico quando a janela foi ocultada com hide()
      LoggerService.info('👁️ Chamando show()...');
      await windowManager.show();
      await Future.delayed(const Duration(milliseconds: 200));

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
        await windowManager.show();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Focar a janela
      LoggerService.info('🎯 Focando janela...');
      await windowManager.focus();
      await Future.delayed(const Duration(milliseconds: 100));

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
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (e, stackTrace) {
      LoggerService.error('❌ Erro ao mostrar janela', e, stackTrace);
      // Tentar método alternativo
      try {
        LoggerService.info('🔄 Tentando método alternativo...');
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.show();
        await windowManager.focus();
      } catch (e2) {
        LoggerService.error('❌ Erro crítico ao mostrar janela', e2);
        rethrow;
      }
    }
  }

  Future<void> restore() async {
    await windowManager.restore();
    await Future.delayed(const Duration(milliseconds: 200));
    await show();
  }

  Future<void> hide() async {
    await windowManager.hide();
  }

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
    return await windowManager.isVisible();
  }

  Future<bool> isMinimized() async {
    return await windowManager.isMinimized();
  }

  Future<bool> isFocused() async {
    return await windowManager.isFocused();
  }

  // WindowListener callbacks
  @override
  void onWindowMinimize() {
    if (_minimizeToTray) {
      hide().catchError((e) {
        LoggerService.error('Erro ao ocultar janela ao minimizar', e);
      });
    }
    _onMinimize?.call();
  }

  @override
  void onWindowClose() async {
    LoggerService.debug('Tentativa de fechar janela');
    
    // Verificar se o fechamento está sendo prevenido (ex: durante OAuth)
    try {
      final isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose) {
        LoggerService.debug('Fechamento prevenido - ignorando evento de fechamento');
        return;
      }
    } catch (e) {
      LoggerService.warning('Erro ao verificar preventClose: $e');
    }
    
    if (_closeToTray) {
      await hide();
    } else {
      _onClose?.call();
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
    windowManager.removeListener(this);
  }
}
