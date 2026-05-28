import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/route_names.dart';

/// Centralizes runtime behavior gates for server vs client mode.
abstract final class AppModePolicy {
  static bool get isClient => currentAppMode == AppMode.client;

  static bool get isServer => currentAppMode == AppMode.server;

  static bool get shouldStartSocketServer => isServer;

  static bool get shouldStartLocalSchedulerInUi => !isClient;

  static bool get shouldAutoConnectSavedServers => isClient;

  static bool isRouteAllowedInCurrentMode(String path) {
    if (!isClient) return true;
    return !_clientBlockedRoutes.contains(path);
  }

  /// Server-only routes blocked when running in client mode.
  ///
  /// Local SGBD configuration pages (SQL Server, Sybase, …) live under one
  /// page (`DatabaseConfigPage`) reused for every native driver. Every new
  /// local-SGBD route MUST be added here when introduced, otherwise the
  /// client would bypass the mode gate by typing the URL directly.
  static const Set<String> _clientBlockedRoutes = {
    RouteNames.sqlServerConfig,
    RouteNames.sybaseConfig,
    RouteNames.schedules,
    RouteNames.serverSettings,
    RouteNames.logs,
    RouteNames.notifications,
  };

  static String redirectForBlockedClientRoute(String _) {
    return RouteNames.dashboard;
  }
}
