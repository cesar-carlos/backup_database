import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../helpers/mock_repositories.dart';

void main() {
  late MockSqlServerConfigRepository mockSqlRepo;
  late MockSybaseConfigRepository mockSybaseRepo;
  late MockPostgresConfigRepository mockPostgresRepo;
  late MockFirebirdConfigRepository mockFirebirdRepo;
  late MockBackupDestinationRepository mockDestRepo;
  late MockScheduleRepository mockScheduleRepo;
  late MockToolVerificationService mockToolVerification;
  late MockLicensePolicyService mockLicensePolicy;
  late MockLicenseValidationService mockLicenseValidation;
  late MockLicenseRepository mockLicenseRepo;
  late MockDeviceKeyService mockDeviceKey;

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    mockSqlRepo = MockSqlServerConfigRepository();
    mockSybaseRepo = MockSybaseConfigRepository();
    mockPostgresRepo = MockPostgresConfigRepository();
    mockFirebirdRepo = MockFirebirdConfigRepository();
    mockDestRepo = MockBackupDestinationRepository();
    mockScheduleRepo = MockScheduleRepository();
    mockToolVerification = MockToolVerificationService();
    mockLicensePolicy = MockLicensePolicyService();
    mockLicenseValidation = MockLicenseValidationService();
    mockLicenseRepo = MockLicenseRepository();
    mockDeviceKey = MockDeviceKeyService();
  });

  License regressionLicense() => License(
    deviceKey: 'test-key',
    licenseKey: 'test-license',
    allowedFeatures: const [
      LicenseFeatures.differentialBackup,
      LicenseFeatures.logBackup,
      LicenseFeatures.verifyIntegrity,
      LicenseFeatures.checksum,
      LicenseFeatures.postBackupScript,
    ],
    expiresAt: DateTime.now().add(const Duration(days: 365)),
  );

  List<BackupDestination> sampleDestinations() => [
    BackupDestination(
      id: 'dest-1',
      name: 'Local',
      type: DestinationType.local,
      config: '{"path":"C:/backup"}',
    ),
  ];

  Widget buildHarness({
    required List<SqlServerConfig> sqlConfigs,
    required List<SybaseConfig> sybaseConfigs,
    required List<PostgresConfig> postgresConfigs,
    required License license,
    List<FirebirdConfig> firebirdConfigs = const [],
  }) {
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
      () => mockDestRepo.getAll(),
    ).thenAnswer((_) async => rd.Success(sampleDestinations()));
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
    when(() => mockToolVerification.verifyFirebirdCliTools()).thenAnswer(
      (_) async => const rd.Success(true),
    );
    when(() => mockToolVerification.verifyPostgresTools()).thenAnswer(
      (_) async => const rd.Success(true),
    );
    when(() => mockLicenseValidation.getCurrentLicense()).thenAnswer(
      (_) async => rd.Success(license),
    );
    // `LicenseProvider.loadLicense` agora consulta `getStoredLicense`
    // (auditoria 2026-05-28).
    when(() => mockLicenseValidation.getStoredLicense()).thenAnswer(
      (_) async => rd.Success(license),
    );
    when(
      () => mockDeviceKey.getDeviceKey(),
    ).thenAnswer((_) async => const rd.Success('test-device-key'));

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
      mockToolVerification,
    );
    final firebirdProvider = FirebirdConfigProvider(
      mockFirebirdRepo,
      mockScheduleRepo,
      mockToolVerification,
    );
    final destProvider = DestinationProvider(
      mockDestRepo,
      mockScheduleRepo,
      mockLicensePolicy,
    );
    final licenseProvider = LicenseProvider(
      validationService: mockLicenseValidation,
      generationService: MockLicenseGenerationService(),
      licenseRepository: mockLicenseRepo,
      deviceKeyService: mockDeviceKey,
    );

    return FluentApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(1920, 1080),
          textScaler: TextScaler.linear(0.9),
        ),
        child: MultiProvider(
          providers: [
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
            ChangeNotifierProvider<DestinationProvider>.value(
              value: destProvider,
            ),
            ChangeNotifierProvider<LicenseProvider>.value(
              value: licenseProvider,
            ),
          ],
          child: const ScheduleDialog(),
        ),
      ),
    );
  }

  Future<void> openSettingsTab(WidgetTester tester) async {
    await tester.tap(find.text(ScheduleDialogStrings.tabSettings));
    await tester.pumpAndSettle();
  }

  Future<void> selectDatabaseType(
    WidgetTester tester,
    String titleLabel,
  ) async {
    await tester.tap(find.text('SQL Server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(titleLabel));
    await tester.pumpAndSettle();
  }

  Future<void> selectDatabaseConfigContaining(
    WidgetTester tester,
    String nameSubstring,
  ) async {
    final placeholder = find.text('Selecione uma configuração');
    await tester.ensureVisible(placeholder);
    await tester.tap(placeholder, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(nameSubstring));
    await tester.pumpAndSettle();
  }

  SqlServerConfig sqlConfig() => SqlServerConfig(
    id: 'sql-reg-1',
    name: 'SQL Reg',
    server: 'localhost',
    database: DatabaseName('master'),
    username: 'sa',
    password: 'x',
  );

  SybaseConfig sybaseConfig() => SybaseConfig(
    id: 'syb-reg-1',
    name: 'Sybase Reg',
    serverName: 'localhost',
    databaseName: DatabaseName('demo'),
    username: 'dba',
    password: 'x',
  );

  PostgresConfig postgresConfig() => PostgresConfig(
    id: 'pg-reg-1',
    name: 'Postgres Reg',
    host: 'localhost',
    database: DatabaseName('postgres'),
    username: 'u',
    password: 'p',
  );

  FirebirdConfig firebirdConfig() => FirebirdConfig(
    id: 'fb-reg-1',
    name: 'FB Reg',
    host: 'localhost',
    databaseFile: r'C:\data\reg.fdb',
    username: 'sysdba',
    password: 'masterkey',
  );

  group('ScheduleDialog settings tab regression', () {
    testWidgets(
      'SQL Server shows advanced performance section on Configurações',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildHarness(
            sqlConfigs: [sqlConfig()],
            sybaseConfigs: const [],
            postgresConfigs: const [],
            license: regressionLicense(),
          ),
        );
        await tester.pumpAndSettle();

        await openSettingsTab(tester);

        expect(
          find.text('Performance Avançada (SQL Server)'),
          findsOneWidget,
        );
        expect(find.text('Performance Avançada (Sybase)'), findsNothing);
      },
    );

    testWidgets(
      'Sybase shows advanced performance section on Configurações',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildHarness(
            sqlConfigs: const [],
            sybaseConfigs: [sybaseConfig()],
            postgresConfigs: const [],
            license: regressionLicense(),
          ),
        );
        await tester.pumpAndSettle();

        await selectDatabaseType(tester, 'Sybase SQL Anywhere');
        await selectDatabaseConfigContaining(tester, 'Sybase Reg');
        await openSettingsTab(tester);

        expect(find.text('Performance Avançada (SQL Server)'), findsNothing);
        expect(
          find.text('Performance Avançada (Sybase)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PostgreSQL hides SQL/Sybase advanced sections on Configurações',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildHarness(
            sqlConfigs: const [],
            sybaseConfigs: const [],
            postgresConfigs: [postgresConfig()],
            license: regressionLicense(),
          ),
        );
        await tester.pumpAndSettle();

        await selectDatabaseType(tester, 'PostgreSQL');
        await selectDatabaseConfigContaining(tester, 'Postgres Reg');
        await openSettingsTab(tester);

        expect(find.text('Performance Avançada (SQL Server)'), findsNothing);
        expect(find.text('Performance Avançada (Sybase)'), findsNothing);
        expect(
          find.text(ScheduleDialogStrings.timeoutsSection),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Firebird shows advanced summary on Configurações when config '
      'selected',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildHarness(
            sqlConfigs: const [],
            sybaseConfigs: const [],
            postgresConfigs: const [],
            firebirdConfigs: [firebirdConfig()],
            license: regressionLicense(),
          ),
        );
        await tester.pumpAndSettle();

        await selectDatabaseType(tester, 'Firebird');
        await selectDatabaseConfigContaining(tester, 'FB Reg');
        await openSettingsTab(tester);

        expect(find.text('Performance Avançada (SQL Server)'), findsNothing);
        expect(find.text('Performance Avançada (Sybase)'), findsNothing);
        expect(find.text('Modo embedded'), findsOneWidget);
        expect(find.text('Service manager (gbak / nbackup)'), findsOneWidget);
      },
    );

    testWidgets(
      'Firebird shows warning on Configurações when no config selected',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildHarness(
            sqlConfigs: const [],
            sybaseConfigs: const [],
            postgresConfigs: const [],
            firebirdConfigs: [firebirdConfig()],
            license: regressionLicense(),
          ),
        );
        await tester.pumpAndSettle();

        await selectDatabaseType(tester, 'Firebird');
        await openSettingsTab(tester);

        expect(find.text('Performance Avançada (SQL Server)'), findsNothing);
        expect(find.text('Performance Avançada (Sybase)'), findsNothing);
        expect(
          find.text('Nenhuma configuração selecionada'),
          findsOneWidget,
        );
      },
    );
  });
}
