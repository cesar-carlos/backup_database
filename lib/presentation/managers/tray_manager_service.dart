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
    trayManager.addListener(this);

    try {
      final iconPath = await _getTrayIconPath();
      final iconFile = File(iconPath);

      if (iconFile.existsSync()) {
        await trayManager.setIcon(iconFile.absolute.path);
      } else {
        final executablePath = Platform.resolvedExecutable;
        await trayManager.setIcon(executablePath);
      }
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao configurar ícone da bandeja', e, stackTrace);
      try {
        final executablePath = Platform.resolvedExecutable;
        await trayManager.setIcon(executablePath);
      } catch (e2) {
        LoggerService.error('Erro crítico ao configurar ícone', e2);
      }
    }

    await trayManager.setToolTip('Backup Database - Ativo');
    await Future.delayed(const Duration(milliseconds: 100));

    await _updateMenu();
    await Future.delayed(const Duration(milliseconds: 100));

    _isInitialized = true;
    LoggerService.info('TrayManager inicializado');
  }

  Future<String> _getTrayIconPath() async {
    if (Platform.isWindows) {
      if (_cachedIconPath != null) {
        final cachedFile = File(_cachedIconPath!);
        if (cachedFile.existsSync()) {
          return _cachedIconPath!;
        }
      }

      try {
        final tempDir = await getTemporaryDirectory();
        final iconFile = File('${tempDir.path}\\tray_icon.ico');
        final ByteData data = await rootBundle.load('assets/icons/favicon.ico');
        final Uint8List bytes = data.buffer.asUint8List();

        await iconFile.writeAsBytes(bytes);
        _cachedIconPath = iconFile.absolute.path;
        return _cachedIconPath!;
      } catch (e) {
        LoggerService.warning('Não foi possível copiar ícone dos assets: $e');
      }

      final executablePath = Platform.resolvedExecutable;
      final executableDir = Directory(executablePath).parent.path;

      final paths = [
        '$executableDir\\data\\flutter_assets\\assets\\icons\\favicon.ico',
        '${Directory(executablePath).parent.parent.path}\\data\\flutter_assets\\assets\\icons\\favicon.ico',
        '$executableDir\\assets\\icons\\favicon.ico',
        '$executableDir\\resources\\app_icon.ico',
      ];

      for (final path in paths) {
        final file = File(path);
        if (file.existsSync()) {
          return file.absolute.path;
        }
      }

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

      return executablePath;
    }
    return 'assets/icons/favicon.ico';
  }

  Future<void> _updateMenu() async {
    try {
      final menu = Menu(
        items: [
          MenuItem(key: 'show', label: 'Abrir'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Sair'),
        ],
      );

      await trayManager.setContextMenu(menu);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao configurar menu de contexto', e, stackTrace);
      rethrow;
    }
  }

  Future<void> setSchedulerPaused(bool paused) async {
    _isSchedulerPaused = paused;
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

  @override
  void onTrayIconMouseDown() {
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
  void onTrayIconRightMouseDown() {
    _showContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {}

  Future<void> _showContextMenu() async {
    if (!_isInitialized) {
      LoggerService.warning('TrayManager não está inicializado');
      return;
    }

    try {
      await _updateMenu();
      await Future.delayed(const Duration(milliseconds: 50));
      await trayManager.popUpContextMenu();
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao exibir menu de contexto', e, stackTrace);
    }
  }

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

      case 'exit':
        _onMenuAction?.call(TrayMenuAction.exit);
        break;

      default:
        LoggerService.warning('Item de menu desconhecido: ${menuItem.key}');
    }
  }

  void dispose() {
    trayManager.removeListener(this);
    trayManager.destroy();
  }
}
