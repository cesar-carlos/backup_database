import 'dart:io';

import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BootstrapConfig {
  const BootstrapConfig({
    required this.appMode,
    required this.singleInstanceEnabled,
    required this.uiSingleInstanceLockFallbackMode,
    required this.uiSchedulerFallbackMode,
  });

  final AppMode appMode;
  final bool singleInstanceEnabled;
  final SingleInstanceLockFallbackMode uiSingleInstanceLockFallbackMode;
  final UiSchedulerFallbackMode uiSchedulerFallbackMode;
}

class BootstrapConfigResolver {
  BootstrapConfigResolver({
    this.environment,
    this.isDebugMode = kDebugMode,
    String? resolvedExecutablePath,
    void Function(String message)? onWarning,
  }) : _resolvedExecutablePath = resolvedExecutablePath,
       _onWarning = onWarning;

  final Map<String, String>? environment;
  final bool isDebugMode;
  final String? _resolvedExecutablePath;
  final void Function(String message)? _onWarning;

  BootstrapConfig resolve({
    required List<String> rawArgs,
  }) {
    final envValues = environment ?? dotenv.env;
    final executablePath =
        _resolvedExecutablePath ?? Platform.resolvedExecutable;

    final appMode = resolveAppMode(
      args: rawArgs,
      isDebugMode: isDebugMode,
      debugAppMode: envValues['DEBUG_APP_MODE'],
      appModeEnv: envValues['APP_MODE'],
      installModeContent: _readInstallModeContent(
        executablePath,
        onWarning: _onWarning,
      ),
      legacyModeContent: _readLegacyModeContent(
        executablePath,
        onWarning: _onWarning,
      ),
    );

    return BootstrapConfig(
      appMode: appMode,
      singleInstanceEnabled: _resolveSingleInstanceEnabled(
        isDebugMode: isDebugMode,
        envValue: envValues['SINGLE_INSTANCE_ENABLED'],
      ),
      uiSingleInstanceLockFallbackMode:
          SingleInstanceConfig.lockFallbackModeFromEnvValue(
            envValues['SINGLE_INSTANCE_LOCK_FALLBACK_MODE'],
          ),
      uiSchedulerFallbackMode: parseUiSchedulerFallbackMode(
        envValues['UI_SCHEDULER_FALLBACK_MODE'],
        onWarning: _onWarning,
      ),
    );
  }

  /// Resolução explícita do flag de instância única:
  ///
  /// - **Release** (`isDebugMode=false`): SEMPRE `true`. O env é
  ///   ignorado intencionalmente para evitar que alguém deixe um
  ///   `SINGLE_INSTANCE_ENABLED=false` no `.env` de produção e
  ///   acidentalmente permita 2 instâncias rodando.
  /// - **Debug** (`isDebugMode=true`): segue o env (default `true`),
  ///   permitindo desabilitar localmente para iterar.
  static bool _resolveSingleInstanceEnabled({
    required bool isDebugMode,
    required String? envValue,
  }) {
    if (!isDebugMode) {
      return true;
    }
    return SingleInstanceConfig.isEnabledFromEnvValue(envValue);
  }

  static UiSchedulerFallbackMode parseUiSchedulerFallbackMode(
    String? raw, {
    void Function(String message)? onWarning,
  }) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return UiSchedulerFallbackMode.failOpen;
    }

    if (normalized == 'fail_safe') return UiSchedulerFallbackMode.failSafe;
    if (normalized == 'fail_open') return UiSchedulerFallbackMode.failOpen;

    onWarning?.call(
      '[main] UI_SCHEDULER_FALLBACK_MODE="$raw" nao reconhecido. '
      'Valores aceitos: "fail_safe" ou "fail_open". Usando fail_open.',
    );
    return UiSchedulerFallbackMode.failOpen;
  }

  static String? _readInstallModeContent(
    String executablePath, {
    void Function(String message)? onWarning,
  }) {
    try {
      final exeDir = File(executablePath).parent;
      final installModeFile = File(
        '${exeDir.path}${Platform.pathSeparator}.install_mode',
      );
      if (installModeFile.existsSync()) {
        return installModeFile.readAsStringSync();
      }
    } on Object catch (e) {
      onWarning?.call(
        '[main] falha ao ler .install_mode: $e (mantendo fallback de modo)',
      );
    }
    return null;
  }

  static String? _readLegacyModeContent(
    String executablePath, {
    void Function(String message)? onWarning,
  }) {
    try {
      final exeDir = File(executablePath).parent;
      final modeFile = File(
        '${exeDir.path}${Platform.pathSeparator}config'
        '${Platform.pathSeparator}mode.ini',
      );
      if (modeFile.existsSync()) {
        return modeFile.readAsStringSync();
      }
    } on Object catch (e) {
      onWarning?.call(
        '[main] falha ao ler config/mode.ini: $e (mantendo fallback de modo)',
      );
    }
    return null;
  }
}
