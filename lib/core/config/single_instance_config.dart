import 'package:flutter_dotenv/flutter_dotenv.dart';

enum SingleInstanceLockFallbackMode {
  failOpen,
  failSafe,
}

/// Configuration for single instance behavior.
///
/// Controls whether the application should enforce single instance mode
/// and provides constants for IPC communication.
class SingleInstanceConfig {
  SingleInstanceConfig._();

  static String? _envValue(String key) {
    try {
      return dotenv.env[key];
    } on Object {
      return null;
    }
  }

  static bool isEnabledFromEnvValue(String? envValue) {
    if (envValue != null) {
      final normalizedValue = envValue.trim().toLowerCase();
      if (normalizedValue == 'true') {
        return true;
      }
      if (normalizedValue == 'false') {
        return false;
      }
    }
    return true;
  }

  static SingleInstanceLockFallbackMode lockFallbackModeFromEnvValue(
    String? envValue,
  ) {
    if (envValue != null) {
      final normalizedValue = envValue.trim().toLowerCase();
      if (normalizedValue == 'fail_open') {
        return SingleInstanceLockFallbackMode.failOpen;
      }
      if (normalizedValue == 'fail_safe') {
        return SingleInstanceLockFallbackMode.failSafe;
      }
    }
    return SingleInstanceLockFallbackMode.failSafe;
  }

  /// Whether single instance enforcement is enabled.
  ///
  /// Priority:
  /// 1. Environment variable `SINGLE_INSTANCE_ENABLED` (true/false)
  /// 2. Default: true (enabled)
  static bool get isEnabled {
    return isEnabledFromEnvValue(_envValue('SINGLE_INSTANCE_ENABLED'));
  }

  static SingleInstanceLockFallbackMode get lockFallbackMode {
    return lockFallbackModeFromEnvValue(
      _envValue('SINGLE_INSTANCE_LOCK_FALLBACK_MODE'),
    );
  }

  static SingleInstanceLockFallbackMode lockFallbackModeFor({
    required bool isServiceMode,
  }) {
    if (isServiceMode) {
      return SingleInstanceLockFallbackMode.failSafe;
    }
    return lockFallbackMode;
  }

  static Duration durationFromSecondsEnvValue({
    required String? envValue,
    required Duration fallback,
    int minSeconds = 1,
    int? maxSeconds,
  }) {
    final parsed = int.tryParse(envValue?.trim() ?? '');
    if (parsed == null || parsed < minSeconds) {
      return fallback;
    }
    if (maxSeconds != null && parsed > maxSeconds) {
      return fallback;
    }
    return Duration(seconds: parsed);
  }

  static const String instanceMutexName =
      r'Global\BackupDatabase_InstanceMutex_{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}';
  static const String uiMutexName = instanceMutexName;
  static const String serviceMutexName = instanceMutexName;

  // IPC configuration
  static const int ipcBasePort = 58724;
  static const List<int> ipcAlternativePorts = [
    58725,
    58726,
    58727,
    58728,
    58729,
  ];

  // Retry configuration
  ///
  /// Pior caso de janela morta ao acionar SHOW_WINDOW antes do dialog:
  /// `maxRetryAttempts * (showWindowConnectTimeout + retryDelay)`.
  /// Com 3 * (1000 + 100) = 3,3s, é tolerável para o usuário desktop.
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(milliseconds: 100);

  // Timeout configuration
  static const Duration connectionTimeout = Duration(seconds: 1);
  static const Duration defaultIpcConnectTimeout = Duration(seconds: 5);
  static const Duration defaultScheduledDelegationTimeout = Duration(hours: 24);
  static const Duration quickConnectionTimeout = Duration(milliseconds: 500);
  static const Duration socketCloseDelay = Duration(milliseconds: 100);
  static const Duration ipcDiscoveryFastTimeout = Duration(milliseconds: 150);
  static const Duration ipcDiscoverySlowTimeout = Duration(milliseconds: 300);
  static const Duration ipcPortCacheTtl = Duration(minutes: 2);

  /// Timeout para o comando `SHOW_WINDOW` enviado pela 2ª instância à
  /// dona do lock. Mantido CURTO (loopback é local) para evitar a
  /// percepção de "app travado" quando o usuário clica no atalho —
  /// pior caso, `maxRetryAttempts * (this + retryDelay)` define o
  /// teto da janela morta antes do dialog de aviso aparecer.
  static const Duration showWindowConnectTimeout = Duration(seconds: 1);

  static Duration get ipcConnectTimeout => durationFromSecondsEnvValue(
    envValue: _envValue('SINGLE_INSTANCE_IPC_CONNECT_TIMEOUT_SECONDS'),
    fallback: defaultIpcConnectTimeout,
    maxSeconds: 300,
  );

  static Duration get scheduledDelegationTimeout => durationFromSecondsEnvValue(
    envValue: _envValue('SCHEDULED_DELEGATION_TIMEOUT_SECONDS'),
    fallback: defaultScheduledDelegationTimeout,
  );

  // IPC commands (legacy ping/pong still accepted by server for older clients)
  static const String ipcProtocolId = 'BACKUP_DATABASE_IPC_V1';
  static const int ipcProtocolVersion = 1;
  static const String ipcInstanceRoleUi = 'ui';
  static const String ipcInstanceRoleService = 'service';

  static String get ipcPingMessage => '$ipcProtocolId|PING';
  static String get ipcPongLinePrefix => '$ipcProtocolId|PONG|';
  static String get ipcUserInfoLinePrefix => '$ipcProtocolId|USER_INFO|';
  static String get ipcGetUserInfoMessage => '$ipcProtocolId|GET_USER_INFO';
  static String get ipcShowWindowMessage => '$ipcProtocolId|SHOW_WINDOW';
  static const String ipcRunScheduleCommand = 'RUN_SCHEDULE';
  static const String ipcRunScheduleResultCommand = 'RUN_SCHEDULE_RESULT';
  static const String ipcRunScheduleMessageOk = 'ok';
  static const String ipcRunScheduleMessageInvalidScheduleId =
      'invalid_schedule_id';
  static const String ipcRunScheduleMessageOwnerCannotRunSchedule =
      'owner_cannot_run_schedule';
  static const String ipcRunScheduleMessageExecutionFailed = 'execution_failed';
  static const String ipcRunScheduleMessageDelegationTimeout =
      'delegation_timeout';
  static String ipcRunScheduleMessage(String scheduleId) =>
      '$ipcProtocolId|$ipcRunScheduleCommand|scheduleId=$scheduleId';
  static String get ipcRunScheduleResultLinePrefix =>
      '$ipcProtocolId|$ipcRunScheduleResultCommand|';

  static const String showWindowCommand = 'SHOW_WINDOW';
  static const String getUserInfoCommand = 'GET_USER_INFO';
  static const String userInfoResponsePrefix = 'USER_INFO:';
  static const String pingCommand = 'PING';
  static const String pongResponse = 'PONG';

  // CLI arguments
  static const String minimizedArgument = '--minimized';

  static const String launchOriginArgumentPrefix = '--launch-origin=';

  static const String windowsStartupLaunchOriginValue = 'windows-startup';

  static String get windowsStartupLaunchOriginArgument =>
      '$launchOriginArgumentPrefix$windowsStartupLaunchOriginValue';

  static const String startupLaunchArgument = '--startup-launch';

  static bool machineStartupArgsNeedProtocolMigration(String arguments) {
    final trimmed = arguments.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    if (trimmed.contains(startupLaunchArgument)) {
      return true;
    }
    if (!trimmed.contains(windowsStartupLaunchOriginArgument)) {
      return true;
    }
    return false;
  }
}
