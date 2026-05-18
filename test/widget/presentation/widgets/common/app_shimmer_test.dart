import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/providers/skeleton_loading_preference_provider.dart';
import 'package:backup_database/presentation/widgets/atoms/app_shimmer.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

void main() {
  testWidgets(
    'AppShimmer builds when SkeletonLoadingPreferenceProvider is absent',
    (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.lightFluentTheme,
          home: const ScaffoldPage(
            content: AppShimmer(
              child: SizedBox(height: 40, width: 200),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Shimmer), findsOneWidget);
    },
  );

  testWidgets('AppShimmer disables Shimmer when preference is off', (
    WidgetTester tester,
  ) async {
    final prefs = _PrefsSkeletonDisabled();
    final provider = SkeletonLoadingPreferenceProvider(
      userPreferencesRepository: prefs,
    );
    await provider.initialize();

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: ChangeNotifierProvider<SkeletonLoadingPreferenceProvider>.value(
          value: provider,
          child: const ScaffoldPage(
            content: AppShimmer(
              child: SizedBox(height: 40, width: 200),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final shimmer = tester.widget<Shimmer>(find.byType(Shimmer));
    expect(shimmer.enabled, isFalse);
  });
}

class _PrefsSkeletonDisabled implements IUserPreferencesRepository {
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
  Future<String?> getUiDensity() async => null;

  @override
  Future<bool> getSkeletonLoadingEnabled() async => false;

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
  Future<void> setUiDensity(String name) async {}

  @override
  Future<void> setSkeletonLoadingEnabled(bool value) async {}

  @override
  Future<bool> getUseSystemAccentColor() async => false;

  @override
  Future<bool> getUseWindowsMicaBackdrop() async => true;

  @override
  Future<void> setUseSystemAccentColor(bool value) async {}

  @override
  Future<void> setUseWindowsMicaBackdrop(bool value) async {}

  @override
  Future<bool> getLocalScheduleTimerEnabled() async => true;

  @override
  Future<void> setLocalScheduleTimerEnabled(bool value) async {}
}
