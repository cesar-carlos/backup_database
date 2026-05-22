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

/// Returns the database filename for the current app mode.
/// Server uses the default database for backward compatibility.
/// Client uses a separate database to avoid conflicts.
String getDatabaseNameForMode(AppMode mode) {
  return switch (mode) {
    AppMode.client => 'backup_database_client',
    AppMode.server => 'backup_database',
    AppMode.unified => 'backup_database',
  };
}

AppMode? parseAppModeValue(String? raw) {
  final normalized = raw?.trim().toLowerCase();
  return switch (normalized) {
    'server' => AppMode.server,
    'client' => AppMode.client,
    'unified' => AppMode.unified,
    _ => null,
  };
}

AppMode resolveAppMode({
  required List<String> args,
  required bool isDebugMode,
  String? debugAppMode,
  String? appModeEnv,
  String? installModeContent,
  String? legacyModeContent,
}) {
  // 1. Command line arguments
  for (final arg in args) {
    if (arg == '--mode=server') return AppMode.server;
    if (arg == '--mode=client') return AppMode.client;
  }

  // 2. Debug/development only: DEBUG_APP_MODE
  if (isDebugMode) {
    final debugResolved = parseAppModeValue(debugAppMode);
    if (debugResolved != null) {
      return debugResolved;
    }
  }

  // 3. Environment variable
  final envResolved = parseAppModeValue(appModeEnv);
  if (envResolved != null) {
    return envResolved;
  }

  // 4. .install_mode file created by installer
  final installModeResolved = parseAppModeValue(installModeContent);
  if (installModeResolved != null) {
    return installModeResolved;
  }

  // 5. Legacy config/mode.ini file
  final modeIni = legacyModeContent;
  if (modeIni != null) {
    if (RegExp(
      r'mode\s*=\s*server',
      caseSensitive: false,
    ).hasMatch(modeIni)) {
      return AppMode.server;
    }
    if (RegExp(
      r'mode\s*=\s*client',
      caseSensitive: false,
    ).hasMatch(modeIni)) {
      return AppMode.client;
    }
  }

  // 6. Default to server mode
  return AppMode.server;
}
