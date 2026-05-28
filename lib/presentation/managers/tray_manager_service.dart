import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/constants/app_image_assets.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

enum TrayMenuAction {
  show,
  executeBackup,
  pauseScheduler,
  resumeScheduler,
  settings,
  exit,
}

class TrayManagerService with TrayListener {
  factory TrayManagerService() => _instance;
  TrayManagerService._();
  static final TrayManagerService _instance = TrayManagerService._();

  Function(TrayMenuAction)? _onMenuAction;
  bool _isSchedulerPaused = false;
  bool _isInitialized = false;
  String? _cachedIconPath;
  String? _cachedTrayKey;

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
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao configurar ícone da bandeja', e, stackTrace);
      try {
        final executablePath = Platform.resolvedExecutable;
        await trayManager.setIcon(executablePath);
      } on Object catch (e2) {
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

  /// Chave de cache do icone na bandeja.
  ///
  /// Combina versao + buildNumber do app com SHA-256 do `app_tray.ico` no
  /// bundle. Garante que qualquer upgrade (mesmo patch) OU qualquer
  /// substituicao da arte do icone (mesmo entre builds com a mesma versao)
  /// gera uma chave nova — o arquivo cacheado em `%TEMP%` recebe nome
  /// diferente, e o Windows passa a exibir o icone correto sem cache
  /// agressivo. Alinhado ao pipeline de icones validado por
  /// `scripts/verify_windows_icons.py`.
  Future<String> _trayCacheKey() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final data = await rootBundle.load(AppImageAssets.trayIco);
    final digest = sha256.convert(data.buffer.asUint8List());
    final hashPrefix = digest.toString().substring(0, 16);
    return '${packageInfo.version}_${packageInfo.buildNumber}_$hashPrefix';
  }

  /// Best-effort: remove icones de bandeja antigos do `%TEMP%`.
  ///
  /// Em upgrades anteriores, a chave de cache muda (sha+version), entao
  /// arquivos `tray_icon_<chave>.ico` antigos ficam orfaos. Nao e leak
  /// critico (o OS cuida do TEMP), mas evita acumular dezenas de copias
  /// ao longo de varios upgrades.
  Future<void> _cleanupStaleTrayIcons(String currentCacheKey) async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) return;
      final currentName = 'tray_icon_$currentCacheKey.ico';
      await for (final entity in tempDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('tray_icon_') &&
            name.endsWith('.ico') &&
            name != currentName) {
          try {
            await entity.delete();
          } on Object {
            // Outro processo pode estar segurando o arquivo; tudo bem,
            // tentaremos de novo no proximo startup.
          }
        }
      }
    } on Object catch (e) {
      LoggerService.warning('Falha ao limpar icones antigos do tray: $e');
    }
  }

  Future<String> _getTrayIconPath() async {
    if (Platform.isWindows) {
      final cacheKey = await _trayCacheKey();
      if (_cachedIconPath != null && _cachedTrayKey == cacheKey) {
        final cachedFile = File(_cachedIconPath!);
        if (cachedFile.existsSync()) {
          return _cachedIconPath!;
        }
      }

      try {
        final tempDir = await getTemporaryDirectory();
        final iconFile = File('${tempDir.path}\\tray_icon_$cacheKey.ico');
        final data = await rootBundle.load(AppImageAssets.trayIco);
        final bytes = data.buffer.asUint8List();

        await iconFile.writeAsBytes(bytes);
        _cachedIconPath = iconFile.absolute.path;
        _cachedTrayKey = cacheKey;
        // Limpa copias de versoes anteriores em background — nao bloqueia o
        // startup do tray.
        unawaited(_cleanupStaleTrayIcons(cacheKey));
        return _cachedIconPath!;
      } on Object catch (e) {
        LoggerService.warning('Não foi possível copiar ícone dos assets: $e');
      }

      final executablePath = Platform.resolvedExecutable;
      final executableDir = Directory(executablePath).parent.path;

      final trayIco = AppImageAssets.trayIco.replaceAll('/', r'\');
      final paths = [
        '$executableDir\\data\\flutter_assets\\$trayIco',
        '${Directory(executablePath).parent.parent.path}\\data\\flutter_assets\\$trayIco',
        '$executableDir\\$trayIco',
        '$executableDir\\resources\\app_icon.ico',
      ];

      for (final path in paths) {
        final file = File(path);
        if (file.existsSync()) {
          return file.absolute.path;
        }
      }

      var currentDir = Directory(executablePath).parent;
      for (var i = 0; i < 6; i++) {
        final iconPath = '${currentDir.path}\\$trayIco';
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
    return AppImageAssets.trayIco;
  }

  Future<void> _updateMenu() async {
    try {
      final locale = appLocaleFromPlatform();
      final menu = Menu(
        items: [
          MenuItem(
            key: 'show',
            label: appLocaleStringForLocale(locale, 'Abrir', 'Open'),
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'settings',
            label: appLocaleStringForLocale(
              locale,
              'Configurações',
              'Settings',
            ),
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit',
            label: appLocaleStringForLocale(locale, 'Sair', 'Exit'),
          ),
        ],
      );

      await trayManager.setContextMenu(menu);
    } on Object catch (e, stackTrace) {
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
    unawaited(
      Future.delayed(const Duration(milliseconds: 200), () {
        unawaited(
          _restoreWindow()
              .then((_) {
                _onMenuAction?.call(TrayMenuAction.show);
              })
              .catchError((e) {
                LoggerService.error('Erro ao restaurar janela do tray', e);
              }),
        );
      }),
    );
  }

  @override
  void onTrayIconMouseUp() {
    unawaited(
      _restoreWindow()
          .then((_) {
            _onMenuAction?.call(TrayMenuAction.show);
          })
          .catchError((e) {
            LoggerService.error('Erro ao restaurar janela do tray', e);
          }),
    );
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
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao restaurar janela', e, stackTrace);
      try {
        await windowManager.setSkipTaskbar(false);
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.show();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.focus();
      } on Object catch (e2) {
        LoggerService.error('Erro crítico ao restaurar janela', e2);
      }
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_showContextMenu());
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
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao exibir menu de contexto', e, stackTrace);
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(
          _restoreWindow()
              .then((_) {
                _onMenuAction?.call(TrayMenuAction.show);
              })
              .catchError((e) {
                LoggerService.error('Erro ao restaurar janela do menu', e);
              }),
        );

      case 'settings':
        _onMenuAction?.call(TrayMenuAction.settings);

      case 'exit':
        _onMenuAction?.call(TrayMenuAction.exit);

      default:
        LoggerService.warning('Item de menu desconhecido: ${menuItem.key}');
    }
  }

  void dispose() {
    trayManager.removeListener(this);
    unawaited(trayManager.destroy());
  }
}
