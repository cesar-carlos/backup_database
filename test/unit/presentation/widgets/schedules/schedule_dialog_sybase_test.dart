import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_backup_schedule.dart';
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
    mockDestRepo = MockBackupDestinationRepository();
    mockScheduleRepo = MockScheduleRepository();
    mockToolVerification = MockToolVerificationService();
    mockLicensePolicy = MockLicensePolicyService();
    mockLicenseValidation = MockLicenseValidationService();
    mockLicenseRepo = MockLicenseRepository();
    mockDeviceKey = MockDeviceKeyService();
  });

  Widget buildScheduleDialogHarness({
    Schedule? schedule,
    List<SybaseConfig> sybaseConfigs = const [],
    List<BackupDestination> destinations = const [],
    License? license,
  }) {
    when(() => mockSqlRepo.getAll())
        .thenAnswer((_) async => const rd.Success(<SqlServerConfig>[]));
    when(() => mockSybaseRepo.getAll())
        .thenAnswer((_) async => rd.Success(sybaseConfigs));
    when(() => mockPostgresRepo.getAll())
        .thenAnswer((_) async => const rd.Success(<PostgresConfig>[]));
    when(() => mockDestRepo.getAll())
        .thenAnswer((_) async => rd.Success(destinations));
    when(() => mockToolVerification.verifySqlCmd())
        .thenAnswer((_) async => const rd.Success(true));
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
    when(() => mockLicenseValidation.getCurrentLicense()).thenAnswer(
      (_) async => license != null
          ? rd.Success(license)
          : rd.Failure(Exception('No license')),
    );
    when(() => mockDeviceKey.getDeviceKey())
        .thenAnswer((_) async => const rd.Success('test-device-key'));

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
            ChangeNotifierProvider<DestinationProvider>.value(
              value: destProvider,
            ),
            ChangeNotifierProvider<LicenseProvider>.value(
              value: licenseProvider,
            ),
          ],
          child: ScheduleDialog(schedule: schedule),
        ),
      ),
    );
  }

  SybaseConfig sybaseConfig({String id = 'sybase-cfg-1'}) => SybaseConfig(
        id: id,
        name: 'Sybase Test',
        serverName: 'localhost',
        databaseName: DatabaseName('testdb'),
        username: 'sa',
        password: 'secret',
      );

  License licenseWithLogAndDifferential() => License(
        deviceKey: 'test-key',
        licenseKey: 'test-license',
        allowedFeatures: const [
          LicenseFeatures.differentialBackup,
          LicenseFeatures.logBackup,
        ],
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );

  group('ScheduleDialog - Sybase backup types', () {
    testWidgets(
      'new Sybase schedule shows only Full and Log (no Differential)',
      (tester) async {
        await tester.pumpWidget(
          buildScheduleDialogHarness(
            sybaseConfigs: [sybaseConfig()],
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithLogAndDifferential(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('SQL Server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sybase SQL Anywhere'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Full').at(0));
        await tester.pumpAndSettle();

        expect(find.text('Full'), findsAtLeast(1));
        expect(find.text('Log de Transações'), findsOneWidget);
        expect(find.text('Diferencial'), findsNothing);
      },
    );

    testWidgets(
      'legacy Sybase schedule with isConvertedDifferential shows Differential as Incremental (Transaction Log)',
      (tester) async {
        final schedule = SybaseBackupSchedule(
          name: 'Legacy Sybase',
          databaseConfigId: 'sybase-cfg-1',
          databaseType: DatabaseType.sybase,
          scheduleType: 'daily',
          scheduleConfig: '{}',
          destinationIds: const ['dest-1'],
          backupFolder: r'C:\backup',
          backupType: BackupType.differential,
          isConvertedDifferential: true,
        );

        await tester.pumpWidget(
          buildScheduleDialogHarness(
            schedule: schedule,
            sybaseConfigs: [sybaseConfig()],
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithLogAndDifferential(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Full').at(0));
        await tester.pumpAndSettle();

        expect(find.text('Incremental (Transaction Log)'), findsOneWidget);
        expect(find.text('Full'), findsAtLeast(1));
        expect(find.text('Log de Transações'), findsOneWidget);
      },
    );
  });
}
