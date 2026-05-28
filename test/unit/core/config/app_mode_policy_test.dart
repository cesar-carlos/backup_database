import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/app_mode_policy.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppMode? previousMode;

  setUp(() {
    previousMode = currentAppMode;
  });

  tearDown(() {
    if (previousMode != null) {
      setAppMode(previousMode!);
    }
  });

  group('AppModePolicy — server mode', () {
    setUp(() => setAppMode(AppMode.server));

    test('should allow all routes', () {
      expect(
        AppModePolicy.isRouteAllowedInCurrentMode(RouteNames.schedules),
        isTrue,
      );
      expect(
        AppModePolicy.isRouteAllowedInCurrentMode(RouteNames.logs),
        isTrue,
      );
    });

    test('should start socket server and local UI scheduler', () {
      expect(AppModePolicy.shouldStartSocketServer, isTrue);
      expect(AppModePolicy.shouldStartLocalSchedulerInUi, isTrue);
      expect(AppModePolicy.shouldAutoConnectSavedServers, isFalse);
      expect(AppModePolicy.isServer, isTrue);
      expect(AppModePolicy.isClient, isFalse);
    });
  });

  group('AppModePolicy — client mode', () {
    setUp(() => setAppMode(AppMode.client));

    test('should block server-only routes', () {
      const blocked = [
        RouteNames.sqlServerConfig,
        RouteNames.sybaseConfig,
        RouteNames.schedules,
        RouteNames.serverSettings,
        RouteNames.logs,
        RouteNames.notifications,
      ];

      for (final path in blocked) {
        expect(
          AppModePolicy.isRouteAllowedInCurrentMode(path),
          isFalse,
          reason: path,
        );
      }
    });

    test('should allow client routes', () {
      expect(
        AppModePolicy.isRouteAllowedInCurrentMode(RouteNames.dashboard),
        isTrue,
      );
      expect(
        AppModePolicy.isRouteAllowedInCurrentMode(RouteNames.remoteSchedules),
        isTrue,
      );
      expect(
        AppModePolicy.isRouteAllowedInCurrentMode(RouteNames.serverLogin),
        isTrue,
      );
    });

    test('redirectForBlockedClientRoute should target dashboard', () {
      expect(
        AppModePolicy.redirectForBlockedClientRoute(RouteNames.logs),
        RouteNames.dashboard,
      );
    });

    test('should skip socket server and local scheduler', () {
      expect(AppModePolicy.shouldStartSocketServer, isFalse);
      expect(AppModePolicy.shouldStartLocalSchedulerInUi, isFalse);
      expect(AppModePolicy.shouldAutoConnectSavedServers, isTrue);
      expect(AppModePolicy.isClient, isTrue);
      expect(AppModePolicy.isServer, isFalse);
    });
  });
}
