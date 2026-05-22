import 'dart:io';

import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/presentation/pages/remote_schedules_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../helpers/fake_remote_schedules_connection_manager.dart';
import '../../../helpers/stub_temp_directory_service.dart';

class _MockServerConnectionRepository extends Mock
    implements IServerConnectionRepository {}

class _MockConnectionLogRepository extends Mock
    implements IConnectionLogRepository {}

void main() {
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
  late ServerConnectionProvider serverConnectionProvider;
  late RemoteSchedulesProvider remoteSchedulesProvider;
  late StubTempDirectoryService tempDirectoryService;

  setUp(() {
    connectionManager = FakeRemoteSchedulesConnectionManager(
      simulateConnected: false,
    );
    serverRepository = _MockServerConnectionRepository();
    connectionLogRepository = _MockConnectionLogRepository();
    tempDirectoryService = StubTempDirectoryService();

    when(
      () => serverRepository.getAll(),
    ).thenAnswer((_) async => const rd.Success(<ServerConnection>[]));
    when(
      () => connectionLogRepository.insertAttempt(
        clientHost: any(named: 'clientHost'),
        success: any(named: 'success'),
        serverId: any(named: 'serverId'),
        errorMessage: any(named: 'errorMessage'),
        clientId: any(named: 'clientId'),
      ),
    ).thenAnswer((_) async => const rd.Success(rd.unit));

    serverConnectionProvider = ServerConnectionProvider(
      serverRepository,
      connectionManager,
      connectionLogRepository,
    );
    remoteSchedulesProvider = RemoteSchedulesProvider(
      connectionManager,
      tempDirectoryService: tempDirectoryService,
    );
  });

  tearDown(() async {
    remoteSchedulesProvider.dispose();
    serverConnectionProvider.dispose();
    await connectionManager.disconnect();
  });

  testWidgets(
    'shows disconnected empty state with connect CTA',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('pt', 'BR'),
          theme: AppTheme.lightFluentTheme,
          darkTheme: AppTheme.darkFluentTheme,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ServerConnectionProvider>.value(
                value: serverConnectionProvider,
              ),
              ChangeNotifierProvider<RemoteSchedulesProvider>.value(
                value: remoteSchedulesProvider,
              ),
            ],
            child: const RemoteSchedulesPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Conecte-se a um servidor'), findsOneWidget);
      expect(
        find.text(
          'Vá em Conectar para adicionar e conectar a um servidor, depois volte aqui para ver e controlar os agendamentos.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ir para Conectar'), findsOneWidget);
    },
  );

  testWidgets(
    'shows server queue card title when connected with queue items',
    (WidgetTester tester) async {
      connectionManager.simulateConnected = true;
      connectionManager.simulateQueueSupported = true;

      final schedule = Schedule(
        name: 'Nightly SQL',
        databaseConfigId: 'db-1',
        databaseType: DatabaseType.sqlServer,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const [],
        backupFolder: r'C:\backups',
        id: 'sched-queue-1',
      );

      connectionManager.listSchedulesResult = rd.Success([schedule]);
      connectionManager.executionQueueResult = rd.Success(
        ExecutionQueueResult(
          queue: [
            QueuedExecution(
              runId: 'run-queued-1',
              scheduleId: schedule.id,
              queuedAt: DateTime.utc(2026, 5, 22),
              queuedPosition: 1,
            ),
          ],
          totalQueued: 1,
          maxQueueSize: 50,
          serverTimeUtc: DateTime.utc(2026, 5, 22),
        ),
      );

      await remoteSchedulesProvider.loadSchedules();
      await remoteSchedulesProvider.loadExecutionQueue();

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('pt', 'BR'),
          theme: AppTheme.lightFluentTheme,
          darkTheme: AppTheme.darkFluentTheme,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ServerConnectionProvider>.value(
                value: serverConnectionProvider,
              ),
              ChangeNotifierProvider<RemoteSchedulesProvider>.value(
                value: remoteSchedulesProvider,
              ),
            ],
            child: const RemoteSchedulesPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Fila no servidor'), findsOneWidget);
      expect(find.text('Nightly SQL'), findsAtLeastNWidgets(1));
    },
  );
}
