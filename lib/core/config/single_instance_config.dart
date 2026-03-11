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

  /// Whether single instance enforcement is enabled.
  ///
  /// Priority:
  /// 1. Environment variable `SINGLE_INSTANCE_ENABLED` (true/false)
  /// 2. Default: true (enabled)
  static bool get isEnabled {
    final envValue = dotenv.env['SINGLE_INSTANCE_ENABLED'];
    if (envValue != null) {
      final normalizedValue = envValue.trim().toLowerCase();
      if (normalizedValue == 'true') {
        return true;
      }
      if (normalizedValue == 'false') {
        return false;
      }
      return true;
    }
    return true;
  }

  static SingleInstanceLockFallbackMode get lockFallbackMode {
    final envValue = dotenv.env['SINGLE_INSTANCE_LOCK_FALLBACK_MODE'];
    if (envValue != null) {
      final normalizedValue = envValue.trim().toLowerCase();
      if (normalizedValue == 'fail_safe') {
        return SingleInstanceLockFallbackMode.failSafe;
      }
    }
    return SingleInstanceLockFallbackMode.failOpen;
  }

  // Mutex configuration
  static const String uiMutexName =
      r'Global\BackupDatabase_UIMutex_{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}';
  static const String serviceMutexName =
      r'Global\BackupDatabase_ServiceMutex_{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}';

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
  static const int maxRetryAttempts = 5;
  static const Duration retryDelay = Duration(milliseconds: 200);

  // Timeout configuration
  static const Duration connectionTimeout = Duration(seconds: 1);
  static const Duration quickConnectionTimeout = Duration(milliseconds: 500);
  static const Duration socketCloseDelay = Duration(milliseconds: 100);
  static const Duration ipcDiscoveryFastTimeout = Duration(milliseconds: 150);
  static const Duration ipcDiscoverySlowTimeout = Duration(milliseconds: 300);
  static const Duration ipcPortCacheTtl = Duration(minutes: 2);

  // IPC commands
  static const String showWindowCommand = 'SHOW_WINDOW';
  static const String getUserInfoCommand = 'GET_USER_INFO';
  static const String userInfoResponsePrefix = 'USER_INFO:';
  static const String pingCommand = 'PING';
  static const String pongResponse = 'PONG';

  // CLI arguments
  static const String minimizedArgument = '--minimized';
  static const String startupLaunchArgument = '--startup-launch';
}
