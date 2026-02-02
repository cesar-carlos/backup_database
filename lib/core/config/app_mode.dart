import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum AppMode { server, client, unified }

AppMode? _currentMode;

AppMode get currentAppMode => _currentMode ?? AppMode.unified;

void setAppMode(AppMode mode) {
  _currentMode = mode;
}

const _baseTitle = 'Backup Database';

String getWindowTitleForMode(AppMode mode) {
  return switch (mode) {
    AppMode.server => '$_baseTitle (Servidor)',
    AppMode.client => '$_baseTitle (Cliente)',
    AppMode.unified => _baseTitle,
  };
}

AppMode getAppMode(List<String> args) {
  // 1. Command line arguments
  for (final arg in args) {
    if (arg == '--mode=server') return AppMode.server;
    if (arg == '--mode=client') return AppMode.client;
  }

  // 2. Debug/development only: DEBUG_APP_MODE in .env (ignored in release)
  if (kDebugMode) {
    final debugMode = dotenv.env['DEBUG_APP_MODE']?.trim().toLowerCase();
    if (debugMode == 'server') return AppMode.server;
    if (debugMode == 'client') return AppMode.client;
  }

  // 3. Environment variable (any build)
  final modeFromEnv = dotenv.env['APP_MODE']?.toLowerCase();
  if (modeFromEnv == 'server') return AppMode.server;
  if (modeFromEnv == 'client') return AppMode.client;

  // 4. .install_mode file created by installer
  try {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final installModeFile = File(
      '${exeDir.path}${Platform.pathSeparator}.install_mode',
    );
    if (installModeFile.existsSync()) {
      final content = installModeFile.readAsStringSync().trim().toLowerCase();
      if (content == 'server') return AppMode.server;
      if (content == 'client') return AppMode.client;
    }
  } on Object catch (_) {
    // ignore; continue to next check
  }

  // 5. Legacy config/mode.ini file
  try {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final modeFile = File(
      '${exeDir.path}${Platform.pathSeparator}config'
      '${Platform.pathSeparator}mode.ini',
    );
    if (modeFile.existsSync()) {
      final content = modeFile.readAsStringSync();
      if (RegExp(
        r'mode\s*=\s*server',
        caseSensitive: false,
      ).hasMatch(content)) {
        return AppMode.server;
      }
      if (RegExp(
        r'mode\s*=\s*client',
        caseSensitive: false,
      ).hasMatch(content)) {
        return AppMode.client;
      }
    }
  } on Object catch (_) {
    // ignore; fall back to server
  }

  // 6. Default to server mode
  return AppMode.server;
}
