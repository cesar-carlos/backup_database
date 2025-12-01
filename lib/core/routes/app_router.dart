import 'package:go_router/go_router.dart';

import '../constants/route_names.dart';
import '../../presentation/pages/pages.dart';

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
      ],
    ),
  ],
);
