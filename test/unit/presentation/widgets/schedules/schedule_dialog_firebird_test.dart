import 'dart:io';

import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../../helpers/fake_firebird_remote_client_connection_manager.dart';
import '../../../helpers/mock_repositories.dart';

class _MockServerConnectionRepository extends Mock
    implements IServerConnectionRepository {}

class _MockConnectionLogRepository extends Mock
    implements IConnectionLogRepository {}

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
  late _MockServerConnectionRepository mockServerConnRepo;
  late _MockConnectionLogRepository mockConnLogRepo;

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
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
    mockServerConnRepo = _MockServerConnectionRepository();
    mockConnLogRepo = _MockConnectionLogRepository();

    when(
      () => mockServerConnRepo.getAll(),
    ).thenAnswer((_) async => const rd.Success(<ServerConnection>[]));
    when(
      () => mockConnLogRepo.insertAttempt(
        clientHost: any(named: 'clientHost'),
        success: any(named: 'success'),
        serverId: any(named: 'serverId'),
        errorMessage: any(named: 'errorMessage'),
        clientId: any(named: 'clientId'),
      ),
    ).thenAnswer((_) async => const rd.Success(rd.unit));
  });

  Widget buildScheduleDialogHarness({
    List<FirebirdConfig> firebirdConfigs = const [],
    List<BackupDestination> destinations = const [],
    License? license,
    Schedule? schedule,
    ServerConnectionProvider? serverConnectionProvider,
  }) {
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
    ).thenAnswer((_) async => rd.Success(firebirdConfigs));
    when(
      () => mockDestRepo.getAll(),
    ).thenAnswer((_) async => rd.Success(destinations));
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
    when(() => mockLicenseValidation.getCurrentLicense()).thenAnswer(
      (_) async => license != null
          ? rd.Success(license)
          : rd.Failure(Exception('No license')),
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

    final scopedServerConnection = serverConnectionProvider;

    return FluentApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(1920, 1080),
          textScaler: TextScaler.linear(0.9),
        ),
        child: MultiProvider(
          providers: [
            if (scopedServerConnection != null)
              ChangeNotifierProvider<ServerConnectionProvider>.value(
                value: scopedServerConnection,
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

  FirebirdConfig firebirdConfig({String id = 'fb-cfg-1'}) => FirebirdConfig(
    id: id,
    name: 'Firebird Test',
    host: 'localhost',
    databaseFile: r'C:\data\test.fdb',
    username: 'sysdba',
    password: 'masterkey',
  );

  License licenseWithBackupTypesAndVerify() => License(
    deviceKey: 'test-key',
    licenseKey: 'test-license',
    allowedFeatures: const [
      LicenseFeatures.differentialBackup,
      LicenseFeatures.logBackup,
      LicenseFeatures.verifyIntegrity,
    ],
    expiresAt: DateTime.now().add(const Duration(days: 365)),
  );

  Future<void> selectFirebirdDatabaseType(WidgetTester tester) async {
    await tester.tap(find.text('SQL Server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firebird'));
    await tester.pumpAndSettle();
  }

  Schedule firebirdScheduleWithLog() => Schedule(
    name: 'FB nightly',
    databaseConfigId: 'fb-cfg-1',
    databaseType: DatabaseType.firebird,
    scheduleType: 'daily',
    scheduleConfig: '{}',
    destinationIds: const <String>['dest-1'],
    backupFolder: 'bf',
    backupType: BackupType.log,
    id: 'sched-fb-1',
  );

  group('ScheduleDialog - Firebird', () {
    testWidgets(
      'new Firebird schedule lists only Full and Full Single backup types',
      (tester) async {
        await tester.pumpWidget(
          buildScheduleDialogHarness(
            firebirdConfigs: [firebirdConfig()],
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithBackupTypesAndVerify(),
          ),
        );
        await tester.pumpAndSettle();

        await selectFirebirdDatabaseType(tester);

        await tester.tap(find.text('Full').at(0));
        await tester.pumpAndSettle();

        expect(find.text('Full Single'), findsOneWidget);
        expect(find.text('Diferencial'), findsNothing);
        expect(find.text('Log de Transações'), findsNothing);
        expect(find.text('Diferencial (convertido)'), findsNothing);
        expect(find.text('Full Single (convertido)'), findsNothing);
        expect(find.text('Log de Transações (convertido)'), findsNothing);
      },
    );

    testWidgets(
      'editing Firebird schedule with log backup normalizes to Full caption',
      (tester) async {
        await tester.pumpWidget(
          buildScheduleDialogHarness(
            schedule: firebirdScheduleWithLog(),
            firebirdConfigs: [firebirdConfig()],
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithBackupTypesAndVerify(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Diferencial'), findsNothing);
        expect(find.text('Log de Transações'), findsNothing);
        expect(find.textContaining('nbackup'), findsWidgets);
      },
    );

    testWidgets(
      'Verify After Backup info uses Firebird-specific copy when licensed',
      (tester) async {
        const expectedSnippet =
            'Após Full Single (gbak), verifica o .fbk '
            'restaurando para um ficheiro .fdb '
            'temporário local (`gbak -c`) e apaga-o. '
            'Não se aplica a backup físico (nbackup). '
            'Política estrita: falha na verificação '
            'aborta o backup com erro.';

        await tester.pumpWidget(
          buildScheduleDialogHarness(
            firebirdConfigs: [firebirdConfig()],
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithBackupTypesAndVerify(),
          ),
        );
        await tester.pumpAndSettle();

        await selectFirebirdDatabaseType(tester);

        await tester.tap(find.text('Configurações'));
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (widget) => widget is Tooltip && widget.message == expectedSnippet,
          ),
          findsWidgets,
        );
      },
    );
  });

  group('ScheduleDialog — remote client Firebird gate', () {
    tearDown(() {
      setAppMode(AppMode.unified);
    });

    Future<void> openDatabaseTypeDropdown(WidgetTester tester) async {
      await tester.tap(find.text('SQL Server'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'legacy remote client hides Firebird from database type dropdown',
      (WidgetTester tester) async {
        setAppMode(AppMode.client);
        final cm = FakeConnectedLegacyRemoteConnectionManager();
        final scp = ServerConnectionProvider(
          mockServerConnRepo,
          cm,
          mockConnLogRepo,
        );
        addTearDown(() async {
          scp.dispose();
          await cm.disconnect();
        });

        await tester.pumpWidget(
          buildScheduleDialogHarness(
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithBackupTypesAndVerify(),
            serverConnectionProvider: scp,
          ),
        );
        await tester.pumpAndSettle();

        await openDatabaseTypeDropdown(tester);
        expect(find.text('Firebird'), findsNothing);
      },
    );

    testWidgets(
      'Firebird-capable remote client keeps Firebird in database type dropdown',
      (WidgetTester tester) async {
        setAppMode(AppMode.client);
        final cm = FakeConnectedFirebirdCapableRemoteConnectionManager();
        final scp = ServerConnectionProvider(
          mockServerConnRepo,
          cm,
          mockConnLogRepo,
        );
        addTearDown(() async {
          scp.dispose();
          await cm.disconnect();
        });

        await tester.pumpWidget(
          buildScheduleDialogHarness(
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithBackupTypesAndVerify(),
            serverConnectionProvider: scp,
          ),
        );
        await tester.pumpAndSettle();

        await openDatabaseTypeDropdown(tester);
        expect(find.text('Firebird'), findsOneWidget);
      },
    );

    testWidgets(
      'settings tab shows Firebird physical-backup verify guidance for Full',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildScheduleDialogHarness(
            firebirdConfigs: [firebirdConfig()],
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithBackupTypesAndVerify(),
          ),
        );
        await tester.pumpAndSettle();

        await selectFirebirdDatabaseType(tester);
        await tester.tap(find.text(ScheduleDialogStrings.tabSettings));
        await tester.pumpAndSettle();

        expect(find.text('Firebird (backup fisico)'), findsOneWidget);
      },
    );

    testWidgets(
      'settings tab omits Firebird physical verify guidance for Full Single',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildScheduleDialogHarness(
            firebirdConfigs: [firebirdConfig()],
            destinations: [
              BackupDestination(
                id: 'dest-1',
                name: 'Local',
                type: DestinationType.local,
                config: '{"path":"C:/backup"}',
              ),
            ],
            license: licenseWithBackupTypesAndVerify(),
          ),
        );
        await tester.pumpAndSettle();

        await selectFirebirdDatabaseType(tester);
        await tester.tap(find.text('Full').at(0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Full Single'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ScheduleDialogStrings.tabSettings));
        await tester.pumpAndSettle();

        expect(find.text('Firebird (backup fisico)'), findsNothing);
      },
    );
  });
}
