import 'dart:ui' as ui;

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagerService with WindowListener {
  factory WindowManagerService() => _instance;
  WindowManagerService._();
  static final WindowManagerService _instance = WindowManagerService._();

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
      skipTaskbar: startMinimized, // Ocultar da taskbar se iniciar minimizado
      titleBarStyle: TitleBarStyle.normal,
      title: title,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startMinimized) {
        // Quando iniciar minimizado, ocultar a janela e não focar
        await windowManager.hide();
        LoggerService.info('Aplicativo iniciado minimizado (oculto)');
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });

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

    // Garantir que o tamanho mínimo seja aplicado após a inicialização
    await windowManager.setMinimumSize(minimumSize);

    // Configurar preventClose baseado na configuração closeToTray
    await _updatePreventClose(_closeToTray);

    windowManager.addListener(this);
    _isInitialized = true;

    LoggerService.info(
      'WindowManager inicializado - Tamanho mínimo: ${minimumSize.width}x${minimumSize.height}, CloseToTray: $_closeToTray',
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

    // Configurar preventClose baseado na configuração (assíncrono em background)
    _updatePreventClose(value).catchError((e) {
      LoggerService.warning('Erro ao configurar preventClose: $e');
    });
  }

  Future<void> _updatePreventClose(bool closeToTray) async {
    try {
      if (closeToTray) {
        // Quando closeToTray é true, prevenir fechamento padrão
        await windowManager.setPreventClose(true);
        LoggerService.debug('PreventClose ativado - fechar irá para bandeja');
      } else {
        // Quando closeToTray é false, permitir fechamento normal
        await windowManager.setPreventClose(false);
        LoggerService.debug(
          'PreventClose desativado - fechar irá encerrar aplicativo',
        );
      }
    } on Object catch (e) {
      LoggerService.warning('Erro ao configurar preventClose: $e');
    }
  }

  Future<void> show() async {
    try {
      LoggerService.info('🪟 Tentando mostrar janela...');

      // Garantir que a janela apareça na taskbar
      await windowManager.setSkipTaskbar(false);
      await Future.delayed(const Duration(milliseconds: 100));

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
    } on Object catch (e, stackTrace) {
      LoggerService.error('❌ Erro ao mostrar janela', e, stackTrace);
      // Tentar método alternativo
      try {
        LoggerService.info('🔄 Tentando método alternativo...');
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.show();
        await windowManager.focus();
      } on Object catch (e2) {
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
    if (_minimizeToTray) {
      hide().catchError((e) {
        LoggerService.error('Erro ao ocultar janela ao minimizar', e);
      });
    }
    _onMinimize?.call();
  }

  @override
  Future<void> onWindowClose() async {
    LoggerService.info(
      'Tentativa de fechar janela - closeToTray: $_closeToTray',
    );

    // Verificar se o fechamento está sendo prevenido (ex: durante OAuth)
    try {
      final isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose && !_closeToTray) {
        // Se preventClose está ativo por outro motivo (ex: OAuth) e não é closeToTray, ignorar
        LoggerService.debug(
          'Fechamento prevenido por outro motivo - ignorando evento',
        );
        return;
      }
    } on Object catch (e) {
      LoggerService.warning('Erro ao verificar preventClose: $e');
    }

    if (_closeToTray) {
      // Prevenir o fechamento padrão e ocultar para a bandeja
      try {
        // Garantir que preventClose está ativo
        await windowManager.setPreventClose(true);
        // Ocultar a janela
        await hide();
        // Ocultar da taskbar
        await windowManager.setSkipTaskbar(true);
        LoggerService.info(
          '✅ Janela ocultada para a bandeja (fechamento prevenido)',
        );
      } on Object catch (e) {
        LoggerService.error('Erro ao ocultar janela para bandeja', e);
        // Se falhar, tentar apenas ocultar
        try {
          await hide();
          await windowManager.setSkipTaskbar(true);
        } on Object catch (e2) {
          LoggerService.error('Erro crítico ao ocultar janela', e2);
        }
      }
    } else {
      // Permitir fechamento normal
      try {
        // Garantir que preventClose está desativado
        await windowManager.setPreventClose(false);
        LoggerService.info('Fechamento permitido - encerrando aplicativo');
        _onClose?.call();
      } on Object catch (e) {
        LoggerService.error('Erro ao configurar preventClose para fechar', e);
        // Mesmo com erro, tentar fechar
        _onClose?.call();
      }
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
