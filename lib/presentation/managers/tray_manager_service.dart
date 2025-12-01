import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/utils/logger_service.dart';

enum TrayMenuAction {
  show,
  executeBackup,
  pauseScheduler,
  resumeScheduler,
  settings,
  exit,
}

class TrayManagerService with TrayListener {
  static final TrayManagerService _instance = TrayManagerService._();
  factory TrayManagerService() => _instance;
  TrayManagerService._();

  Function(TrayMenuAction)? _onMenuAction;
  bool _isSchedulerPaused = false;
  bool _isInitialized = false;
  String? _cachedIconPath;

  Future<void> initialize({Function(TrayMenuAction)? onMenuAction}) async {
    if (_isInitialized) return;

    _onMenuAction = onMenuAction;

    // Adicionar listener ANTES de configurar o ícone
    trayManager.addListener(this);

    try {
      final iconPath = await _getTrayIconPath();
      final iconFile = File(iconPath);

      if (iconFile.existsSync()) {
        LoggerService.info(
          'Configurando ícone da bandeja: ${iconFile.absolute.path}',
        );
        await trayManager.setIcon(iconFile.absolute.path);
        LoggerService.info('Ícone da bandeja configurado com sucesso');
      } else {
        // Tentar usar o executável diretamente (Windows extrai o ícone automaticamente)
        final executablePath = Platform.resolvedExecutable;
        LoggerService.info(
          'Ícone não encontrado, usando executável: $executablePath',
        );
        await trayManager.setIcon(executablePath);
      }
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao configurar ícone da bandeja', e, stackTrace);
      // Tentar usar o executável como fallback
      try {
        final executablePath = Platform.resolvedExecutable;
        await trayManager.setIcon(executablePath);
        LoggerService.info('Fallback: usando executável como ícone');
      } catch (e2) {
        LoggerService.error('Erro crítico ao configurar ícone', e2);
      }
    }

    await trayManager.setToolTip('Backup Database - Ativo');

    await _updateMenu();

    _isInitialized = true;

    LoggerService.info('TrayManager inicializado');
  }

  Future<String> _getTrayIconPath() async {
    if (Platform.isWindows) {
      // Se já temos o ícone em cache, usar ele
      if (_cachedIconPath != null) {
        final cachedFile = File(_cachedIconPath!);
        if (cachedFile.existsSync()) {
          return _cachedIconPath!;
        }
      }

      // Tentar copiar o favicon.ico dos assets para um arquivo temporário
      try {
        final tempDir = await getTemporaryDirectory();
        final iconFile = File('${tempDir.path}\\tray_icon.ico');

        // Carregar o asset favicon.ico
        final ByteData data = await rootBundle.load('assets/icons/favicon.ico');
        final Uint8List bytes = data.buffer.asUint8List();

        // Salvar em arquivo temporário
        await iconFile.writeAsBytes(bytes);
        _cachedIconPath = iconFile.absolute.path;

        LoggerService.info('Ícone copiado dos assets para: $_cachedIconPath');
        return _cachedIconPath!;
      } catch (e) {
        LoggerService.warning('Não foi possível copiar ícone dos assets: $e');
        // Continuar com outros métodos
      }

      final executablePath = Platform.resolvedExecutable;
      final executableDir = Directory(executablePath).parent.path;

      // Tentar encontrar favicon.ico em múltiplos caminhos possíveis

      // Caminho 1: data/flutter_assets/assets/icons/favicon.ico (modo debug/release)
      final assetPath1 =
          '$executableDir\\data\\flutter_assets\\assets\\icons\\favicon.ico';
      final assetFile1 = File(assetPath1);
      if (assetFile1.existsSync()) {
        return assetFile1.absolute.path;
      }

      // Caminho 2: Subir um nível e procurar data/flutter_assets/assets/icons/favicon.ico
      final parentDir = Directory(executablePath).parent.parent.path;
      final assetPath2 =
          '$parentDir\\data\\flutter_assets\\assets\\icons\\favicon.ico';
      final assetFile2 = File(assetPath2);
      if (assetFile2.existsSync()) {
        return assetFile2.absolute.path;
      }

      // Caminho 3: Procurar assets/icons/favicon.ico relativo ao executável
      final assetPath3 = '$executableDir\\assets\\icons\\favicon.ico';
      final assetFile3 = File(assetPath3);
      if (assetFile3.existsSync()) {
        return assetFile3.absolute.path;
      }

      // Caminho 4: Subir diretórios até encontrar assets/icons/favicon.ico
      var currentDir = Directory(executablePath).parent;
      for (int i = 0; i < 6; i++) {
        final iconPath = '${currentDir.path}\\assets\\icons\\favicon.ico';
        final iconFile = File(iconPath);
        if (iconFile.existsSync()) {
          return iconFile.absolute.path;
        }
        final parent = currentDir.parent;
        if (parent.path == currentDir.path) break;
        currentDir = parent;
      }

      // Caminho 5: Tentar app_icon.ico gerado pelo flutter_launcher_icons
      final appIconPath = '$executableDir\\resources\\app_icon.ico';
      final appIconFile = File(appIconPath);
      if (appIconFile.existsSync()) {
        return appIconFile.absolute.path;
      }

      // Fallback: usar o executável (Windows extrai o ícone automaticamente do .exe)
      return executablePath;
    }
    return 'assets/icons/favicon.ico';
  }

  Future<void> _updateMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: 'Abrir Backup Database'),
        MenuItem.separator(),
        MenuItem(key: 'execute_backup', label: 'Executar Backup Agora'),
        MenuItem(
          key: _isSchedulerPaused ? 'resume_scheduler' : 'pause_scheduler',
          label: _isSchedulerPaused
              ? 'Retomar Agendamentos'
              : 'Pausar Agendamentos',
        ),
        MenuItem.separator(),
        MenuItem(key: 'settings', label: 'Configurações'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Sair'),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  Future<void> setSchedulerPaused(bool paused) async {
    _isSchedulerPaused = paused;
    await _updateMenu();
    await _updateTooltip();
  }

  Future<void> _updateTooltip() async {
    final status = _isSchedulerPaused ? 'Pausado' : 'Ativo';
    await trayManager.setToolTip('Backup Database - $status');
  }

  Future<void> setBackupRunning(bool running, {String? databaseName}) async {
    if (running) {
      await trayManager.setToolTip(
        'Backup Database - Executando backup${databaseName != null ? ': $databaseName' : ''}',
      );
    } else {
      await _updateTooltip();
    }
  }

  // TrayListener callbacks
  @override
  void onTrayIconMouseDown() {
    // No Windows, o MouseUp pode não ser disparado corretamente pelo tray_manager
    // Vamos restaurar também no MouseDown como solução alternativa
    Future.delayed(const Duration(milliseconds: 200), () {
      _restoreWindow()
          .then((_) {
            _onMenuAction?.call(TrayMenuAction.show);
          })
          .catchError((e) {
            LoggerService.error('Erro ao restaurar janela do tray', e);
          });
    });
  }

  @override
  void onTrayIconMouseUp() {
    _restoreWindow()
        .then((_) {
          _onMenuAction?.call(TrayMenuAction.show);
        })
        .catchError((e) {
          LoggerService.error('Erro ao restaurar janela do tray', e);
        });
  }

  Future<void> _restoreWindow() async {
    try {
      await windowManager.setSkipTaskbar(false);
      await Future.delayed(const Duration(milliseconds: 100));

      final isMinimized = await windowManager.isMinimized();
      if (isMinimized) {
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      await windowManager.show();
      await Future.delayed(const Duration(milliseconds: 300));

      final isVisibleAfterShow = await windowManager.isVisible();
      if (!isVisibleAfterShow) {
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.show();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      await windowManager.focus();
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao restaurar janela', e, stackTrace);
      try {
        await windowManager.setSkipTaskbar(false);
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.show();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.focus();
      } catch (e2) {
        LoggerService.error('Erro crítico ao restaurar janela', e2);
      }
    }
  }

  @override
  void onTrayIconRightMouseDown() {}

  @override
  void onTrayIconRightMouseUp() {}

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _restoreWindow()
            .then((_) {
              _onMenuAction?.call(TrayMenuAction.show);
            })
            .catchError((e) {
              LoggerService.error('Erro ao restaurar janela do menu', e);
            });
        break;

      case 'execute_backup':
        _onMenuAction?.call(TrayMenuAction.executeBackup);
        break;

      case 'pause_scheduler':
        _onMenuAction?.call(TrayMenuAction.pauseScheduler);
        break;

      case 'resume_scheduler':
        _onMenuAction?.call(TrayMenuAction.resumeScheduler);
        break;

      case 'settings':
        _restoreWindow()
            .then((_) {
              _onMenuAction?.call(TrayMenuAction.settings);
            })
            .catchError((e) {
              LoggerService.error('Erro ao restaurar janela do menu', e);
            });
        break;

      case 'exit':
        _onMenuAction?.call(TrayMenuAction.exit);
        break;
    }
  }

  void dispose() {
    trayManager.removeListener(this);
    trayManager.destroy();
  }
}
