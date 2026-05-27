// mocktail `when(() => ...)` stubs use statement-style closures.

import 'dart:io';

import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/presentation/pages/database_config_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../helpers/fake_firebird_remote_client_connection_manager.dart';
import '../../../unit/helpers/mock_repositories.dart';

class _MockServerConnectionRepository extends Mock
    implements IServerConnectionRepository {}

class _MockConnectionLogRepository extends Mock
    implements IConnectionLogRepository {}

void main() {
  late MockSqlServerConfigRepository mockSqlRepo;
  late MockSybaseConfigRepository mockSybaseRepo;
  late MockPostgresConfigRepository mockPostgresRepo;
  late MockFirebirdConfigRepository mockFirebirdRepo;
  late MockScheduleRepository mockScheduleRepo;
  late MockToolVerificationService mockToolVerification;
  late _MockServerConnectionRepository mockServerConnRepo;
  late _MockConnectionLogRepository mockConnLogRepo;

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
    mockScheduleRepo = MockScheduleRepository();
    mockToolVerification = MockToolVerificationService();
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

  tearDown(() {
    setAppMode(AppMode.unified);
  });

  Future<void> pumpClientDatabaseConfigPage(
    WidgetTester tester, {
    required ConnectionManager connectionManager,
    List<FirebirdConfig> firebirdConfigs = const <FirebirdConfig>[],
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
    when(
      () => mockToolVerification.verifyPostgresTools(),
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
      mockToolVerification,
    );
    final firebirdProvider = FirebirdConfigProvider(
      mockFirebirdRepo,
      mockScheduleRepo,
      mockToolVerification,
    );

    final serverConnectionProvider = ServerConnectionProvider(
      mockServerConnRepo,
      connectionManager,
      mockConnLogRepo,
    );

    addTearDown(sqlProvider.dispose);
    addTearDown(sybaseProvider.dispose);
    addTearDown(postgresProvider.dispose);
    addTearDown(firebirdProvider.dispose);
    addTearDown(() async {
      serverConnectionProvider.dispose();
      await connectionManager.disconnect();
    });

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        darkTheme: AppTheme.darkFluentTheme,
        locale: const Locale('en', 'US'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1400, 3200)),
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<ServerConnectionProvider>.value(
                value: serverConnectionProvider,
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
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'client mode connected to legacy server hides Firebird from list and dialog on '
    'database_config_page',
    (WidgetTester tester) async {
      setAppMode(AppMode.client);
      final connectionManager = FakeConnectedLegacyRemoteConnectionManager();
      expect(connectionManager.isConnected, isTrue);
      expect(connectionManager.isFirebirdSupported, isFalse);

      await pumpClientDatabaseConfigPage(
        tester,
        connectionManager: connectionManager,
        firebirdConfigs: [
          FirebirdConfig(
            id: 'fb-hidden',
            name: 'Legacy Firebird',
            host: 'legacy-host',
            databaseFile: 'C:/legacy.fdb',
            username: 'sysdba',
            password: 'p',
            port: PortNumber(3050),
          ),
        ],
      );

      expect(find.text('Legacy Firebird'), findsNothing);
      expect(find.text('Firebird'), findsNothing);

      await tester.tap(find.text('New configuration').first);
      await tester.pumpAndSettle();
      expect(find.text('Firebird'), findsNothing);
    },
  );

  testWidgets(
    'client mode connected to Firebird-capable server shows Firebird in list and dialog '
    'on database_config_page',
    (WidgetTester tester) async {
      setAppMode(AppMode.client);
      final connectionManager =
          FakeConnectedFirebirdCapableRemoteConnectionManager();
      expect(connectionManager.isConnected, isTrue);
      expect(connectionManager.isFirebirdSupported, isTrue);

      await pumpClientDatabaseConfigPage(
        tester,
        connectionManager: connectionManager,
        firebirdConfigs: [
          FirebirdConfig(
            id: 'fb-visible',
            name: 'Visible Firebird',
            host: 'fb-host',
            databaseFile: 'C:/visible.fdb',
            username: 'sysdba',
            password: 'p',
            port: PortNumber(3050),
          ),
        ],
      );

      expect(find.text('Visible Firebird'), findsOneWidget);
      expect(find.text('Firebird'), findsWidgets);

      await tester.tap(find.text('New configuration').first);
      await tester.pumpAndSettle();
      expect(find.text('Firebird'), findsWidgets);
    },
  );
}
