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
  static const Set<String> _clientBlockedRoutes = {
    RouteNames.sqlServerConfig,
    RouteNames.schedules,
    RouteNames.serverSettings,
    RouteNames.logs,
    RouteNames.notifications,
  };

  static String redirectForBlockedClientRoute(String _) {
    return RouteNames.dashboard;
  }
}
