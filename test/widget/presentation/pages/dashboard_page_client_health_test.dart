import 'dart:io';

import 'package:backup_database/application/providers/dashboard_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/presentation/pages/dashboard_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../helpers/fake_remote_schedules_connection_manager.dart';

class _MockServerConnectionRepository extends Mock
    implements IServerConnectionRepository {}

class _MockConnectionLogRepository extends Mock
    implements IConnectionLogRepository {}

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

const _degradedHealthMessage = 'Staging disk usage above threshold';

final _savedServer = ServerConnection(
  id: 'conn-1',
  name: 'Lab Server',
  serverId: 'srv-1',
  host: '127.0.0.1',
  port: 9000,
  password: 'secret',
  isOnline: true,
  createdAt: DateTime.utc(2026, 5, 22),
  updatedAt: DateTime.utc(2026, 5, 22),
);

void main() {
  AppMode? previousMode;

  setUpAll(() {
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
  });

  late FakeRemoteSchedulesConnectionManager connectionManager;
  late _MockServerConnectionRepository serverRepository;
  late _MockConnectionLogRepository connectionLogRepository;
  late _MockBackupHistoryRepository historyRepository;
  late _MockScheduleRepository scheduleRepository;
  late ServerConnectionProvider serverConnectionProvider;
  late DashboardProvider dashboardProvider;

  setUp(() {
    previousMode = currentAppMode;
    setAppMode(AppMode.client);

    connectionManager = FakeRemoteSchedulesConnectionManager();
    connectionManager.serverHealthResult = rd.Success(
      ServerHealth(
        status: ServerHealthStatus.degraded,
        checks: const <String, bool>{'staging': false},
        serverTimeUtc: DateTime.utc(2026, 5, 22),
        uptimeSeconds: 3600,
        message: _degradedHealthMessage,
      ),
    );

    serverRepository = _MockServerConnectionRepository();
    connectionLogRepository = _MockConnectionLogRepository();
    historyRepository = _MockBackupHistoryRepository();
    scheduleRepository = _MockScheduleRepository();

    when(
      () => serverRepository.getAll(),
    ).thenAnswer((_) async => rd.Success(<ServerConnection>[_savedServer]));
    when(
      () => connectionLogRepository.insertAttempt(
        clientHost: any(named: 'clientHost'),
        success: any(named: 'success'),
        serverId: any(named: 'serverId'),
        errorMessage: any(named: 'errorMessage'),
        clientId: any(named: 'clientId'),
      ),
    ).thenAnswer((_) async => const rd.Success(rd.unit));
    when(
      () => historyRepository.getAll(
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
    when(
      () => historyRepository.getByDateRange(any(), any()),
    ).thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
    when(
      scheduleRepository.getEnabled,
    ).thenAnswer((_) async => const rd.Success(<Schedule>[]));

    serverConnectionProvider = ServerConnectionProvider(
      serverRepository,
      connectionManager,
      connectionLogRepository,
    );
    dashboardProvider = DashboardProvider(
      historyRepository,
      scheduleRepository,
      connectionManager: connectionManager,
    );
  });

  tearDown(() async {
    dashboardProvider.dispose();
    serverConnectionProvider.dispose();
    await connectionManager.disconnect();
    if (previousMode != null) {
      setAppMode(previousMode!);
    }
  });

  testWidgets(
    'shows degraded server health InfoBar when connected in client mode',
    (WidgetTester tester) async {
      await serverConnectionProvider.refreshServerStatus();
      await dashboardProvider.loadDashboardData();

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('en', 'US'),
          theme: AppTheme.lightFluentTheme,
          darkTheme: AppTheme.darkFluentTheme,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ServerConnectionProvider>.value(
                value: serverConnectionProvider,
              ),
              ChangeNotifierProvider<DashboardProvider>.value(
                value: dashboardProvider,
              ),
            ],
            child: const DashboardPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(InfoBar), findsWidgets);
      expect(find.text('Server degraded'), findsOneWidget);
      expect(find.text(_degradedHealthMessage), findsOneWidget);
    },
  );
}
