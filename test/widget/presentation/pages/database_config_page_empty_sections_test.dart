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
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/pages/database_config_page.dart';
import 'package:backup_database/presentation/providers/skeleton_loading_preference_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
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

  Future<void> pumpPage(
    WidgetTester tester, {
    List<SqlServerConfig> sqlConfigs = const <SqlServerConfig>[],
    List<SybaseConfig> sybaseConfigs = const <SybaseConfig>[],
    List<PostgresConfig> postgresConfigs = const <PostgresConfig>[],
    List<FirebirdConfig> firebirdConfigs = const <FirebirdConfig>[],
    ThemeMode themeMode = ThemeMode.light,
    SkeletonLoadingPreferenceProvider? skeletonLoadingPreference,
    MediaQueryData? mediaQuery,
  }) async {
    when(
      () => mockSqlRepo.getAll(),
    ).thenAnswer((_) async => rd.Success(sqlConfigs));
    when(
      () => mockSybaseRepo.getAll(),
    ).thenAnswer((_) async => rd.Success(sybaseConfigs));
    when(
      () => mockPostgresRepo.getAll(),
    ).thenAnswer((_) async => rd.Success(postgresConfigs));
    when(
      () => mockFirebirdRepo.getAll(),
    ).thenAnswer((_) async => rd.Success(firebirdConfigs));
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
          data: mediaQuery ?? const MediaQueryData(size: Size(1400, 1800)),
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

  testWidgets(
    'empty page shows single empty state and removes per-type section CTAs',
    (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('No database configuration yet'), findsOneWidget);
      expect(
        find.text('Add connections to use in backups and schedules.'),
        findsOneWidget,
      );
      expect(find.text('New configuration'), findsNWidgets(2));
      expect(find.text('Add configuration (SQL Server)'), findsNothing);
      expect(
        find.text('Add configuration (Sybase SQL Anywhere)'),
        findsNothing,
      );
      expect(find.text('Add configuration (PostgreSQL)'), findsNothing);
      expect(find.text('Add configuration (Firebird)'), findsNothing);
    },
  );

  testWidgets(
    'aggregated list renders mixed database types with chips and active-first ordering',
    (WidgetTester tester) async {
      await pumpPage(
        tester,
        sqlConfigs: [
          SqlServerConfig(
            id: 'sql-zeta',
            name: 'Zeta',
            server: 'sql-host',
            database: DatabaseName('db_sql'),
            username: 'sa',
            password: 'p',
            port: PortNumber(1433),
          ).copyWith(enabled: false),
        ],
        sybaseConfigs: [
          SybaseConfig(
            id: 'syb-beta',
            name: 'Beta',
            serverName: 'syb-host',
            databaseName: DatabaseName('db_syb'),
            username: 'dba',
            password: 'p',
            port: PortNumber(2638),
          ),
        ],
        postgresConfigs: [
          PostgresConfig(
            id: 'pg-alpha',
            name: 'Alpha',
            host: 'pg-host',
            database: DatabaseName('db_pg'),
            username: 'postgres',
            password: 'p',
            port: PortNumber(5432),
          ),
        ],
        firebirdConfigs: [
          FirebirdConfig(
            id: 'fb-gamma',
            name: 'Gamma',
            host: 'fb-host',
            databaseFile: 'C:/data/example.fdb',
            username: 'sysdba',
            password: 'p',
            port: PortNumber(3050),
          ),
        ],
      );

      expect(find.text('Type'), findsOneWidget);
      expect(find.text('SQL Server'), findsOneWidget);
      expect(find.text('Sybase'), findsOneWidget);
      expect(find.text('PostgreSQL'), findsOneWidget);
      expect(find.text('Firebird'), findsOneWidget);

      final alphaTopLeft = tester.getTopLeft(find.text('Alpha'));
      final betaTopLeft = tester.getTopLeft(find.text('Beta'));
      final gammaTopLeft = tester.getTopLeft(find.text('Gamma'));
      final zetaTopLeft = tester.getTopLeft(find.text('Zeta'));

      expect(alphaTopLeft.dy, lessThan(zetaTopLeft.dy));
      expect(betaTopLeft.dy, lessThan(zetaTopLeft.dy));
      expect(gammaTopLeft.dy, lessThan(zetaTopLeft.dy));
      expect(alphaTopLeft.dy, lessThan(betaTopLeft.dy));
      expect(betaTopLeft.dy, lessThan(gammaTopLeft.dy));
    },
  );

  testWidgets(
    'database config page renders aggregated layout in light and dark theme',
    (WidgetTester tester) async {
      for (final mode in <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
      ]) {
        await pumpPage(
          tester,
          themeMode: mode,
          sqlConfigs: [
            SqlServerConfig(
              id: 'sql-theme',
              name: 'ThemeCfg',
              server: 'sql-host',
              database: DatabaseName('db_theme'),
              username: 'sa',
              password: 'p',
              port: PortNumber(1433),
            ),
          ],
        );

        final pageContext = tester.element(find.byType(DatabaseConfigPage));
        expect(
          FluentTheme.of(pageContext).brightness,
          mode == ThemeMode.light ? Brightness.light : Brightness.dark,
        );
        expect(find.text('All configurations'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'aggregated database config page meets text contrast accessibility guideline',
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
          await pumpPage(
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
    'aggregated grid uses Expanded so list fills height below header',
    (WidgetTester tester) async {
      await pumpPage(
        tester,
        sqlConfigs: [
          SqlServerConfig(
            id: 'sql-one',
            name: 'One',
            server: 'sql-host',
            database: DatabaseName('db_one'),
            username: 'sa',
            password: 'p',
            port: PortNumber(1433),
          ),
        ],
        mediaQuery: const MediaQueryData(size: Size(1400, 900)),
      );

      final pageFinder = find.byType(DatabaseConfigPage);
      expect(pageFinder, findsOneWidget);
      expect(
        find.descendant(of: pageFinder, matching: find.byType(Expanded)),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: pageFinder,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w.runtimeType.toString().startsWith('DatabaseConfigDataGrid'),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('One'), findsOneWidget);
    },
  );

  testWidgets(
    'aggregated database config page builds without overflow at 1.5x and 2.0x text scale',
    (WidgetTester tester) async {
      final prefs = _ShimmerOffUserPreferencesRepository();
      final skeletonPrefs = SkeletonLoadingPreferenceProvider(
        userPreferencesRepository: prefs,
      );
      await skeletonPrefs.initialize();
      addTearDown(skeletonPrefs.dispose);

      for (final scale in <double>[1.5, 2]) {
        await pumpPage(
          tester,
          skeletonLoadingPreference: skeletonPrefs,
          mediaQuery: MediaQueryData(
            size: const Size(1400, 1800),
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

  @override
  Future<bool> getLocalScheduleTimerEnabled() async => true;

  @override
  Future<void> setLocalScheduleTimerEnabled(bool value) async {}
}
