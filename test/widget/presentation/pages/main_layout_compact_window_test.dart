import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/pages/main_layout.dart';
import 'package:backup_database/presentation/providers/theme_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../support/feature_availability_test_support.dart';

class _FakeUserPreferencesRepository implements IUserPreferencesRepository {
  @override
  Future<void> ensureTrayDefaults() async {}

  @override
  Future<bool> getCloseToTray() async => false;

  @override
  Future<bool> getDarkMode() async => false;

  @override
  Future<bool> getMinimizeToTray() async => false;

  @override
  Future<String?> getR1MultiProfileLegacyHintLastDismissedSignature() async =>
      null;

  @override
  Future<bool> getSkeletonLoadingEnabled() async => false;

  @override
  Future<String?> getUiDensity() async => null;

  @override
  Future<void> setCloseToTray(bool value) async {}

  @override
  Future<void> setDarkMode(bool value) async {}

  @override
  Future<void> setMinimizeToTray(bool value) async {}

  @override
  Future<void> setR1MultiProfileLegacyHintLastDismissedSignature(
    String signature,
  ) async {}

  @override
  Future<void> setSkeletonLoadingEnabled(bool value) async {}

  @override
  Future<void> setUiDensity(String name) async {}

  @override
  Future<bool> getUseSystemAccentColor() async => false;

  @override
  Future<bool> getUseWindowsMicaBackdrop() async => false;

  @override
  Future<void> setUseSystemAccentColor(bool value) async {}

  @override
  Future<void> setUseWindowsMicaBackdrop(bool value) async {}

  @override
  Future<bool> getLocalScheduleTimerEnabled() async => true;

  @override
  Future<void> setLocalScheduleTimerEnabled(bool value) async {}
}

void main() {
  setUp(() async {
    await registerTestFeatureAvailability();
  });

  tearDown(() async {
    await unregisterTestFeatureAvailability();
    setAppMode(AppMode.unified);
  });

  testWidgets(
    '800x600 is treated as a compact window',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(AppBreakpoints.minimumWindow);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late bool isCompact;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: AppBreakpoints.minimumWindow),
          child: Builder(
            builder: (BuildContext context) {
              isCompact = context.isCompactWindow;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(isCompact, isTrue);
    },
  );

  testWidgets(
    'MainLayout lays out at 800x600 without overflow',
    (WidgetTester tester) async {
      setAppMode(AppMode.server);
      final themeProvider = ThemeProvider(
        userPreferencesRepository: _FakeUserPreferencesRepository(),
      );
      addTearDown(themeProvider.dispose);

      final router = GoRouter(
        initialLocation: RouteNames.dashboard,
        routes: [
          ShellRoute(
            builder: (context, state, child) => MainLayout(child: child),
            routes: [
              GoRoute(
                path: RouteNames.dashboard,
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.binding.setSurfaceSize(AppBreakpoints.minimumWindow);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: FluentApp.router(
            theme: AppTheme.lightFluentTheme,
            darkTheme: AppTheme.darkFluentTheme,
            themeMode: ThemeMode.light,
            locale: const Locale('en', 'US'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(MainLayout), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
