// mocktail `when(() => ...)` stubs use statement-style closures.

import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/pages/database_config_page.dart';
import 'package:backup_database/presentation/providers/skeleton_loading_preference_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../unit/helpers/mock_repositories.dart';

void main() {
  late MockSqlServerConfigRepository mockSqlRepo;
  late MockSybaseConfigRepository mockSybaseRepo;
  late MockPostgresConfigRepository mockPostgresRepo;
  late MockFirebirdConfigRepository mockFirebirdRepo;
  late MockScheduleRepository mockScheduleRepo;
  late MockToolVerificationService mockToolVerification;

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

  setUp(() {
    mockSqlRepo = MockSqlServerConfigRepository();
    mockSybaseRepo = MockSybaseConfigRepository();
    mockPostgresRepo = MockPostgresConfigRepository();
    mockFirebirdRepo = MockFirebirdConfigRepository();
    mockScheduleRepo = MockScheduleRepository();
    mockToolVerification = MockToolVerificationService();
  });

  Future<void> pumpEmptyPage(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
    SkeletonLoadingPreferenceProvider? skeletonLoadingPreference,
    MediaQueryData? mediaQuery,
  }) async {
    when(
      () => mockSqlRepo.getAll(),
    ).thenAnswer((_) async => const rd.Success(<SqlServerConfig>[]));
    when(
      () => mockSybaseRepo.getAll(),
    ).thenAnswer((_) async => const rd.Success(<SybaseConfig>[]));
    when(
      () => mockPostgresRepo.getAll(),
    ).thenAnswer((_) async => const rd.Success(<PostgresConfig>[]));
    when(
      () => mockFirebirdRepo.getAll(),
    ).thenAnswer((_) async => const rd.Success(<FirebirdConfig>[]));
    when(
      () => mockToolVerification.verifySqlCmd(),
    ).thenAnswer((_) async => const rd.Success(true));
    when(() => mockToolVerification.verifySybaseToolsDetailed()).thenAnswer(
      (_) async => const rd.Success(
        SybaseToolsStatus(
          dbisql: SybaseToolStatus.ok,
          dbbackup: SybaseToolStatus.ok,
          dbvalid: SybaseToolStatus.ok,
          dbverify: SybaseToolStatus.ok,
        ),
      ),
    );
    when(
      () => mockToolVerification.verifyFirebirdCliTools(),
    ).thenAnswer((_) async => const rd.Success(true));

    final sqlProvider = SqlServerConfigProvider(
      mockSqlRepo,
      mockScheduleRepo,
      mockToolVerification,
    );
    final sybaseProvider = SybaseConfigProvider(
      mockSybaseRepo,
      mockScheduleRepo,
      mockToolVerification,
    );
    final postgresProvider = PostgresConfigProvider(
      mockPostgresRepo,
      mockScheduleRepo,
    );
    final firebirdProvider = FirebirdConfigProvider(
      mockFirebirdRepo,
      mockScheduleRepo,
      mockToolVerification,
    );

    addTearDown(sqlProvider.dispose);
    addTearDown(sybaseProvider.dispose);
    addTearDown(postgresProvider.dispose);
    addTearDown(firebirdProvider.dispose);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        darkTheme: AppTheme.darkFluentTheme,
        themeMode: themeMode,
        locale: const Locale('en', 'US'),
        home: MediaQuery(
          data: mediaQuery ?? const MediaQueryData(size: Size(1400, 3200)),
          child: MultiProvider(
            providers: [
              if (skeletonLoadingPreference != null)
                ChangeNotifierProvider<SkeletonLoadingPreferenceProvider>.value(
                  value: skeletonLoadingPreference,
                ),
              ChangeNotifierProvider<SqlServerConfigProvider>.value(
                value: sqlProvider,
              ),
              ChangeNotifierProvider<SybaseConfigProvider>.value(
                value: sybaseProvider,
              ),
              ChangeNotifierProvider<PostgresConfigProvider>.value(
                value: postgresProvider,
              ),
              ChangeNotifierProvider<FirebirdConfigProvider>.value(
                value: firebirdProvider,
              ),
            ],
            child: const DatabaseConfigPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollDatabaseConfigListToTop(WidgetTester tester) async {
    final scrollable = find.descendant(
      of: find.byType(DatabaseConfigPage),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsWidgets);
    for (var attempt = 0; attempt < 48; attempt++) {
      if (find.text('Add configuration (SQL Server)').evaluate().isNotEmpty) {
        return;
      }
      await tester.drag(scrollable.first, const Offset(0, 600));
      await tester.pump();
    }
  }

  Future<void> scrollUntilDatabaseConfigTargetVisible(
    WidgetTester tester, {
    required Finder target,
  }) async {
    final scrollable = find.descendant(
      of: find.byType(DatabaseConfigPage),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsWidgets);
    for (var attempt = 0; attempt < 32; attempt++) {
      if (target.evaluate().isNotEmpty) {
        return;
      }
      await tester.drag(scrollable.first, const Offset(0, -500));
      await tester.pump();
    }
  }

  testWidgets(
    'empty lists show U2 placeholder copy and add CTA for all four SGBDs',
    (WidgetTester tester) async {
      await pumpEmptyPage(tester);

      const addLabels = [
        'Add configuration (SQL Server)',
        'Add configuration (Sybase SQL Anywhere)',
        'Add configuration (PostgreSQL)',
        'Add configuration (Firebird)',
      ];

      await scrollDatabaseConfigListToTop(tester);
      await tester.pumpAndSettle();

      for (final label in addLabels) {
        await scrollUntilDatabaseConfigTargetVisible(
          tester,
          target: find.text(label),
        );
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        expect(
          find.text('No configuration registered for this type.'),
          findsAtLeastNWidgets(1),
        );
      }
    },
  );

  testWidgets(
    'empty page renders all four SGBD sections in light and dark Fluent theme',
    (WidgetTester tester) async {
      const addLabels = [
        'Add configuration (SQL Server)',
        'Add configuration (Sybase SQL Anywhere)',
        'Add configuration (PostgreSQL)',
        'Add configuration (Firebird)',
      ];

      for (final mode in <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
      ]) {
        await pumpEmptyPage(tester, themeMode: mode);
        await tester.pumpAndSettle();

        final pageContext = tester.element(
          find.byType(DatabaseConfigPage),
        );
        expect(
          FluentTheme.of(pageContext).brightness,
          mode == ThemeMode.light ? Brightness.light : Brightness.dark,
        );

        await scrollDatabaseConfigListToTop(tester);
        await tester.pumpAndSettle();

        for (final label in addLabels) {
          await scrollUntilDatabaseConfigTargetVisible(
            tester,
            target: find.text(label),
          );
          await tester.pumpAndSettle();
          expect(find.text(label), findsOneWidget);
        }
      }
    },
  );

  testWidgets(
    'empty database config page meets text contrast accessibility guideline '
    '(light and dark)',
    (WidgetTester tester) async {
      final prefs = _ShimmerOffUserPreferencesRepository();
      final skeletonPrefs = SkeletonLoadingPreferenceProvider(
        userPreferencesRepository: prefs,
      );
      await skeletonPrefs.initialize();
      addTearDown(skeletonPrefs.dispose);

      final semanticsHandle = tester.ensureSemantics();
      try {
        for (final mode in <ThemeMode>[
          ThemeMode.light,
          ThemeMode.dark,
        ]) {
          await pumpEmptyPage(
            tester,
            themeMode: mode,
            skeletonLoadingPreference: skeletonPrefs,
          );
          await expectLater(
            tester,
            meetsGuideline(textContrastGuideline),
          );
        }
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'empty database config page builds without overflow at 1.5x and 2.0x '
    'text scale (light)',
    (WidgetTester tester) async {
      final prefs = _ShimmerOffUserPreferencesRepository();
      final skeletonPrefs = SkeletonLoadingPreferenceProvider(
        userPreferencesRepository: prefs,
      );
      await skeletonPrefs.initialize();
      addTearDown(skeletonPrefs.dispose);

      for (final double scale in <double>[1.5, 2.0]) {
        await pumpEmptyPage(
          tester,
          skeletonLoadingPreference: skeletonPrefs,
          mediaQuery: MediaQueryData(
            size: const Size(1400, 3200),
            textScaler: TextScaler.linear(scale),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}

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
}
