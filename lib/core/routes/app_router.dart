import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/presentation/pages/pages.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: RouteNames.dashboard,
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
          path: RouteNames.transferBackups,
          name: RouteNames.transferBackupsName,
          builder: (context, state) => const TransferBackupsPage(),
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
