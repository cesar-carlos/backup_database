import 'package:backup_database/application/providers/dashboard_provider.dart';
import 'package:backup_database/application/providers/log_provider.dart';
import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/application/services/log_service.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/create_schedule.dart';
import 'package:backup_database/domain/use_cases/scheduling/delete_schedule.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:backup_database/presentation/pages/dashboard_page.dart';
import 'package:backup_database/presentation/pages/logs_page.dart';
import 'package:backup_database/presentation/pages/schedules_page.dart';
import 'package:backup_database/presentation/providers/skeleton_loading_preference_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../support/feature_availability_test_support.dart';

FluentThemeData testPageFluentTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? FluentThemeData.dark()
      : FluentThemeData.light();
  return base.copyWith(
    extensions: [
      if (brightness == Brightness.dark) AppSemanticColors.dark,
      if (brightness != Brightness.dark) AppSemanticColors.light,
    ],
  );
}

MediaQueryData pageTestMediaQuery({required double textScale}) {
  return MediaQueryData(
    size: const Size(1400, 3200),
    textScaler: TextScaler.linear(textScale),
  );
}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockSchedulerService extends Mock implements ISchedulerService {}

class _MockCreateSchedule extends Mock implements CreateSchedule {}

class _MockUpdateSchedule extends Mock implements UpdateSchedule {}

class _MockDeleteSchedule extends Mock implements DeleteSchedule {}

class _MockExecuteScheduledBackup extends Mock
    implements ExecuteScheduledBackup {}

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

class _MockBackupLogRepository extends Mock implements IBackupLogRepository {}

class _ShimmerOffUserPreferencesRepository
    implements IUserPreferencesRepository {
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

void main() {
  setUp(() async {
    await registerTestFeatureAvailability();
  });

  tearDown(() async {
    await unregisterTestFeatureAvailability();
  });

  setUpAll(() {
    registerFallbackValue(
      Schedule(
        name: 's',
        databaseConfigId: 'x',
        databaseType: DatabaseType.sqlServer,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const <String>[],
        backupFolder: 'bf',
      ),
    );
  });

  Future<SkeletonLoadingPreferenceProvider>
  createShimmerOffSkeletonPreference() async {
    final provider = SkeletonLoadingPreferenceProvider(
      userPreferencesRepository: _ShimmerOffUserPreferencesRepository(),
    );
    await provider.initialize();
    return provider;
  }

  Future<void> assertTextContrastGuideline(WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    try {
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      handle.dispose();
    }
  }

  testWidgets(
    'SchedulesPage meets text contrast accessibility guideline (light and dark)',
    (WidgetTester tester) async {
      final scheduleRepo = _MockScheduleRepository();
      when(
        scheduleRepo.getAll,
      ).thenAnswer((_) async => const rd.Success(<Schedule>[]));

      final schedulerProvider = SchedulerProvider(
        repository: scheduleRepo,
        schedulerService: _MockSchedulerService(),
        createSchedule: _MockCreateSchedule(),
        updateSchedule: _MockUpdateSchedule(),
        deleteSchedule: _MockDeleteSchedule(),
        executeBackup: _MockExecuteScheduledBackup(),
      );
      addTearDown(schedulerProvider.dispose);

      final skeletonPrefs = await createShimmerOffSkeletonPreference();
      addTearDown(skeletonPrefs.dispose);

      for (final mode in <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
      ]) {
        await tester.pumpWidget(
          FluentApp(
            theme: testPageFluentTheme(Brightness.light),
            darkTheme: testPageFluentTheme(Brightness.dark),
            themeMode: mode,
            locale: const Locale('en', 'US'),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1400, 3200)),
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider<
                    SkeletonLoadingPreferenceProvider
                  >.value(
                    value: skeletonPrefs,
                  ),
                  ChangeNotifierProvider<SchedulerProvider>.value(
                    value: schedulerProvider,
                  ),
                ],
                child: const SchedulesPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await assertTextContrastGuideline(tester);
      }
    },
  );

  testWidgets(
    'DashboardPage meets text contrast accessibility guideline (light and dark)',
    (WidgetTester tester) async {
      final historyRepo = _MockBackupHistoryRepository();
      final scheduleRepo = _MockScheduleRepository();

      when(
        () => historyRepo.getAll(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
      when(
        () => historyRepo.getByDateRange(any(), any()),
      ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
      when(
        scheduleRepo.getEnabled,
      ).thenAnswer((_) async => const rd.Success(<Schedule>[]));

      final dashboardProvider = DashboardProvider(
        historyRepo,
        scheduleRepo,
      );
      addTearDown(dashboardProvider.dispose);

      final skeletonPrefs = await createShimmerOffSkeletonPreference();
      addTearDown(skeletonPrefs.dispose);

      for (final mode in <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
      ]) {
        await tester.pumpWidget(
          FluentApp(
            theme: testPageFluentTheme(Brightness.light),
            darkTheme: testPageFluentTheme(Brightness.dark),
            themeMode: mode,
            locale: const Locale('en', 'US'),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1400, 3200)),
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider<
                    SkeletonLoadingPreferenceProvider
                  >.value(
                    value: skeletonPrefs,
                  ),
                  ChangeNotifierProvider<DashboardProvider>.value(
                    value: dashboardProvider,
                  ),
                ],
                child: const DashboardPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await assertTextContrastGuideline(tester);
      }
    },
  );

  testWidgets(
    'LogsPage meets text contrast accessibility guideline (light and dark)',
    (WidgetTester tester) async {
      final logRepo = _MockBackupLogRepository();
      when(
        () => logRepo.getAll(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => const rd.Success(<BackupLog>[]));

      final logProvider = LogProvider(LogService(logRepo));
      addTearDown(logProvider.dispose);

      final skeletonPrefs = await createShimmerOffSkeletonPreference();
      addTearDown(skeletonPrefs.dispose);

      for (final mode in <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
      ]) {
        await tester.pumpWidget(
          FluentApp(
            theme: testPageFluentTheme(Brightness.light),
            darkTheme: testPageFluentTheme(Brightness.dark),
            themeMode: mode,
            locale: const Locale('en', 'US'),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1400, 3200)),
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider<
                    SkeletonLoadingPreferenceProvider
                  >.value(
                    value: skeletonPrefs,
                  ),
                  ChangeNotifierProvider<LogProvider>.value(
                    value: logProvider,
                  ),
                ],
                child: const LogsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await assertTextContrastGuideline(tester);
      }
    },
  );

  testWidgets(
    'SchedulesPage builds without overflow at 1.5x and 2.0x text scale (light)',
    (WidgetTester tester) async {
      final scheduleRepo = _MockScheduleRepository();
      when(
        scheduleRepo.getAll,
      ).thenAnswer((_) async => const rd.Success(<Schedule>[]));

      final schedulerProvider = SchedulerProvider(
        repository: scheduleRepo,
        schedulerService: _MockSchedulerService(),
        createSchedule: _MockCreateSchedule(),
        updateSchedule: _MockUpdateSchedule(),
        deleteSchedule: _MockDeleteSchedule(),
        executeBackup: _MockExecuteScheduledBackup(),
      );
      addTearDown(schedulerProvider.dispose);

      final skeletonPrefs = await createShimmerOffSkeletonPreference();
      addTearDown(skeletonPrefs.dispose);

      for (final scale in [1.5, 2.0]) {
        await tester.pumpWidget(
          FluentApp(
            theme: testPageFluentTheme(Brightness.light),
            darkTheme: testPageFluentTheme(Brightness.dark),
            themeMode: ThemeMode.light,
            locale: const Locale('en', 'US'),
            home: MediaQuery(
              data: pageTestMediaQuery(textScale: scale),
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider<
                    SkeletonLoadingPreferenceProvider
                  >.value(
                    value: skeletonPrefs,
                  ),
                  ChangeNotifierProvider<SchedulerProvider>.value(
                    value: schedulerProvider,
                  ),
                ],
                child: const SchedulesPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'DashboardPage builds without overflow at 1.5x and 2.0x text scale (light)',
    (WidgetTester tester) async {
      final historyRepo = _MockBackupHistoryRepository();
      final scheduleRepo = _MockScheduleRepository();

      when(
        () => historyRepo.getAll(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
      when(
        () => historyRepo.getByDateRange(any(), any()),
      ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
      when(
        scheduleRepo.getEnabled,
      ).thenAnswer((_) async => const rd.Success(<Schedule>[]));

      final dashboardProvider = DashboardProvider(
        historyRepo,
        scheduleRepo,
      );
      addTearDown(dashboardProvider.dispose);

      final skeletonPrefs = await createShimmerOffSkeletonPreference();
      addTearDown(skeletonPrefs.dispose);

      for (final scale in [1.5, 2.0]) {
        await tester.pumpWidget(
          FluentApp(
            theme: testPageFluentTheme(Brightness.light),
            darkTheme: testPageFluentTheme(Brightness.dark),
            themeMode: ThemeMode.light,
            locale: const Locale('en', 'US'),
            home: MediaQuery(
              data: pageTestMediaQuery(textScale: scale),
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider<
                    SkeletonLoadingPreferenceProvider
                  >.value(
                    value: skeletonPrefs,
                  ),
                  ChangeNotifierProvider<DashboardProvider>.value(
                    value: dashboardProvider,
                  ),
                ],
                child: const DashboardPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'LogsPage builds without overflow at 1.5x and 2.0x text scale (light)',
    (WidgetTester tester) async {
      final logRepo = _MockBackupLogRepository();
      when(
        () => logRepo.getAll(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => const rd.Success(<BackupLog>[]));

      final logProvider = LogProvider(LogService(logRepo));
      addTearDown(logProvider.dispose);

      final skeletonPrefs = await createShimmerOffSkeletonPreference();
      addTearDown(skeletonPrefs.dispose);

      for (final scale in [1.5, 2.0]) {
        await tester.pumpWidget(
          FluentApp(
            theme: testPageFluentTheme(Brightness.light),
            darkTheme: testPageFluentTheme(Brightness.dark),
            themeMode: ThemeMode.light,
            locale: const Locale('en', 'US'),
            home: MediaQuery(
              data: pageTestMediaQuery(textScale: scale),
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider<
                    SkeletonLoadingPreferenceProvider
                  >.value(
                    value: skeletonPrefs,
                  ),
                  ChangeNotifierProvider<LogProvider>.value(
                    value: logProvider,
                  ),
                ],
                child: const LogsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
