import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/pages/main_layout.dart';
import 'package:backup_database/presentation/providers/theme_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
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

({ThemeProvider theme, GoRouter router}) _createServerMainLayoutHarness() {
  final themeProvider = ThemeProvider(
    userPreferencesRepository: _FakeUserPreferencesRepository(),
  );
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
  return (theme: themeProvider, router: router);
}

void main() {
  setUp(() async {
    await registerTestFeatureAvailability();
  });

  tearDown(() async {
    await unregisterTestFeatureAvailability();
    setAppMode(AppMode.unified);
  });

  // meetsGuideline on full MainLayout exceeds practical CI runtime;
  // covered by atom/molecule a11y tests.
  testWidgets(
    'MainLayout meets tap target guidelines (server shell)',
    (WidgetTester tester) async {
      setAppMode(AppMode.server);
      final (:theme, :router) = _createServerMainLayoutHarness();
      addTearDown(theme.dispose);
      addTearDown(router.dispose);
      await theme.initialize();

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: theme,
            child: FluentApp.router(
              theme: AppTheme.lightFluentTheme,
              darkTheme: AppTheme.darkFluentTheme,
              themeMode: ThemeMode.light,
              locale: const Locale('en', 'US'),
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
    },
    skip: true,
  );

  testWidgets(
    'MainLayout Tab traversal keeps a primary focus (server shell)',
    (WidgetTester tester) async {
      setAppMode(AppMode.server);
      final (:theme, :router) = _createServerMainLayoutHarness();
      addTearDown(theme.dispose);
      addTearDown(router.dispose);
      await theme.initialize();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: FluentApp.router(
            theme: AppTheme.lightFluentTheme,
            darkTheme: AppTheme.darkFluentTheme,
            themeMode: ThemeMode.light,
            locale: const Locale('en', 'US'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      for (var i = 0; i < 24; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(
        tester.binding.focusManager.primaryFocus,
        isNotNull,
        reason: 'Tab cycle should leave focus on a focusable descendant',
      );

      for (var i = 0; i < 6; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
      }
      expect(tester.binding.focusManager.primaryFocus, isNotNull);
    },
    // Tab cycle on full MainLayout hangs in widget tests (Fluent focus loop);
    // keyboard a11y covered by critical_keyboard_navigation_test.dart.
    skip: true,
  );
}
