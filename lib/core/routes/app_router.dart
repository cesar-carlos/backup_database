import 'package:backup_database/core/config/app_mode_policy.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/presentation/pages/pages.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

String? appRouteRedirect(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  if (!AppModePolicy.isRouteAllowedInCurrentMode(path)) {
    return AppModePolicy.redirectForBlockedClientRoute(path);
  }
  return null;
}

final appRouter = GoRouter(
  navigatorKey: appNavigatorKey,
  initialLocation: RouteNames.dashboard,
  redirect: appRouteRedirect,
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainLayout(child: child),
      routes: [
        GoRoute(
          path: RouteNames.dashboard,
          name: RouteNames.dashboardName,
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: RouteNames.sqlServerConfig,
          name: RouteNames.sqlServerConfigName,
          builder: (context, state) => const DatabaseConfigPage(),
        ),
        GoRoute(
          path: RouteNames.sybaseConfig,
          name: RouteNames.sybaseConfigName,
          builder: (context, state) => const DatabaseConfigPage(),
        ),
        GoRoute(
          path: RouteNames.destinations,
          name: RouteNames.destinationsName,
          builder: (context, state) => const DestinationsPage(),
        ),
        GoRoute(
          path: RouteNames.schedules,
          name: RouteNames.schedulesName,
          builder: (context, state) => const SchedulesPage(),
        ),
        GoRoute(
          path: RouteNames.logs,
          name: RouteNames.logsName,
          builder: (context, state) => const LogsPage(),
        ),
        GoRoute(
          path: RouteNames.notifications,
          name: RouteNames.notificationsName,
          builder: (context, state) => const NotificationsPage(),
        ),
        GoRoute(
          path: RouteNames.settings,
          name: RouteNames.settingsName,
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: RouteNames.serverSettings,
          name: RouteNames.serverSettingsName,
          builder: (context, state) => const ServerSettingsPage(),
        ),
        GoRoute(
          path: RouteNames.serverLogin,
          name: RouteNames.serverLoginName,
          builder: (context, state) => const ServerLoginPage(),
        ),
        GoRoute(
          path: RouteNames.remoteSchedules,
          name: RouteNames.remoteSchedulesName,
          builder: (context, state) => const RemoteSchedulesPage(),
        ),
        GoRoute(
          path: RouteNames.remoteDatabaseConfigs,
          name: RouteNames.remoteDatabaseConfigsName,
          builder: (context, state) => const RemoteDatabaseConfigsPage(),
        ),
        GoRoute(
          path: RouteNames.connectionLogs,
          name: RouteNames.connectionLogsName,
          builder: (context, state) => const ConnectionLogPage(),
        ),
      ],
    ),
  ],
);
