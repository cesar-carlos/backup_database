import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/routes/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  AppMode? previousMode;

  setUp(() {
    previousMode = currentAppMode;
    setAppMode(AppMode.client);
  });

  tearDown(() {
    if (previousMode != null) {
      setAppMode(previousMode!);
    }
  });

  GoRouter clientModeTestRouter() {
    return GoRouter(
      initialLocation: RouteNames.dashboard,
      redirect: appRouteRedirect,
      routes: [
        ShellRoute(
          builder: (context, state, child) => child,
          routes: [
            GoRoute(
              path: RouteNames.dashboard,
              builder: (context, state) =>
                  const SizedBox(key: Key('dashboard-page')),
            ),
            GoRoute(
              path: RouteNames.schedules,
              builder: (context, state) =>
                  const SizedBox(key: Key('schedules-page')),
            ),
            GoRoute(
              path: RouteNames.logs,
              builder: (context, state) =>
                  const SizedBox(key: Key('logs-page')),
            ),
          ],
        ),
      ],
    );
  }

  testWidgets(
    'should redirect blocked client routes to dashboard',
    (WidgetTester tester) async {
      final router = clientModeTestRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard-page')), findsOneWidget);

      router.go(RouteNames.schedules);
      await tester.pumpAndSettle();

      expect(router.state.uri.path, RouteNames.dashboard);
      expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
      expect(find.byKey(const Key('schedules-page')), findsNothing);
    },
  );

  testWidgets(
    'should allow client-accessible routes without redirect',
    (WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: RouteNames.dashboard,
        redirect: appRouteRedirect,
        routes: [
          GoRoute(
            path: RouteNames.remoteSchedules,
            builder: (context, state) =>
                const SizedBox(key: Key('remote-schedules-page')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go(RouteNames.remoteSchedules);
      await tester.pumpAndSettle();

      expect(router.state.uri.path, RouteNames.remoteSchedules);
      expect(find.byKey(const Key('remote-schedules-page')), findsOneWidget);
    },
  );
}
