import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/environment_loader.dart';
import 'package:backup_database/core/config/process_role.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/presentation/boot/boot.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void _ignoreLog(String _) {}

void _ignoreLogWithError(
  String _, [
  Object? ignoredError,
  StackTrace? ignoredStackTrace,
]) {}

void main() {
  group('AppBootstrap', () {
    setUpAll(() {
      dotenv.loadFromString(envString: 'DUMMY=value');
    });

    test(
      'routes to service mode initializer when context is service',
      () async {
        final events = <String>[];
        final dependencies =
            _buildDependencies(
              context: _serviceContext(),
              events: events,
            ).copyWith(
              runtime: _buildRuntime(events).copyWith(
                initializeServiceMode: () async {
                  events.add('service_init');
                },
              ),
            );

        await AppBootstrap(dependencies: dependencies).start();

        expect(events, ['service_init']);
      },
    );

    test('routes to ui bootstrap when context is not service', () async {
      final events = <String>[];
      final dependencies = _buildDependencies(
        context: _uiContext(),
        events: events,
      );

      await AppBootstrap(dependencies: dependencies).start();

      expect(events, contains('binding'));
      expect(events, isNot(contains('service_init')));
    });

    test('aborts ui boot after second instance is detected', () async {
      final events = <String>[];
      final dependencies = _buildDependencies(
        context: _uiContext(),
        events: events,
        canContinueAfterSingleInstanceCheck: false,
      );

      await AppBootstrap(dependencies: dependencies).start();

      expect(events, contains('single_instance'));
      expect(events, isNot(contains('app_init')));
      expect(events, isNot(contains('run_app')));
    });

    test('executes scheduled backup and exits ui boot early', () async {
      final events = <String>[];
      final dependencies = _buildDependencies(
        context: _uiContext(args: const ['--schedule-id=job-1']),
        events: events,
        launchConfig: const LaunchConfig(
          scheduleId: 'job-1',
          startMinimized: false,
          args: ['--schedule-id=job-1'],
        ),
      );

      await AppBootstrap(dependencies: dependencies).start();

      expect(events, contains('scheduled:job-1'));
      expect(events, isNot(contains('ui_services')));
      expect(events, isNot(contains('run_app')));
    });

    test('does not start socket server in client mode', () async {
      final events = <String>[];
      final dependencies = _buildDependencies(
        context: _uiContext(),
        events: events,
        bootstrapConfig: _bootstrapConfig(appMode: AppMode.client),
      );

      await AppBootstrap(dependencies: dependencies).start();

      expect(events, isNot(contains('queue_init')));
      expect(events, isNot(contains('socket_start')));
      expect(events, contains('run_app'));
    });

    test('skips local scheduler when policy blocks it', () async {
      final events = <String>[];
      final dependencies = _buildDependencies(
        context: _uiContext(),
        events: events,
        shouldSkipScheduler: true,
      );

      await AppBootstrap(dependencies: dependencies).start();

      expect(events, contains('scheduler_policy:failOpen'));
      expect(events, isNot(contains('scheduler_start')));
    });

    test('runs app only after critical initializations', () async {
      final events = <String>[];
      final dependencies = _buildDependencies(
        context: _uiContext(),
        events: events,
      );

      await AppBootstrap(dependencies: dependencies).start();

      expect(
        events,
        [
          'binding',
          'env',
          'config',
          'apply_config',
          'os',
          'single_instance',
          'di',
          'app_init:server',
          'launch_config',
          'ui_services',
          'scheduler_policy:failOpen',
          'scheduler_start',
          'queue_init',
          'cleanup_locks',
          'socket_start',
          'staging_start',
          'temp_cleanup_start',
          'run_app',
        ],
      );
    });

    test('logs bootstrap phases in expected order', () async {
      final infoLogs = <String>[];
      final dependencies = _buildDependencies(
        context: _uiContext(),
        events: <String>[],
        infoLogs: infoLogs,
      );

      await AppBootstrap(dependencies: dependencies).start();

      final phaseLogs = infoLogs
          .where((line) => line.contains('bootstrap_timing phase='))
          .toList();
      expect(
        phaseLogs,
        [
          contains('phase=context_resolved'),
          contains('phase=single_instance_ok'),
          contains('phase=service_locator_ready'),
          contains('phase=app_initializer_done'),
          contains('phase=launch_config_ready'),
          contains('phase=scheduler_and_socket_ready'),
          contains('phase=run_app_called'),
        ],
      );
    });
  });
}

AppBootstrapDependencies _buildDependencies({
  required LaunchBootstrapContext context,
  required List<String> events,
  LaunchConfig? launchConfig,
  BootstrapConfig? bootstrapConfig,
  bool canContinueAfterSingleInstanceCheck = true,
  bool shouldSkipScheduler = false,
  List<String>? infoLogs,
}) {
  final resolvedLaunchConfig =
      launchConfig ??
      LaunchConfig(
        scheduleId: null,
        startMinimized: false,
        args: context.rawArgs,
      );
  final resolvedBootstrapConfig = bootstrapConfig ?? _bootstrapConfig();

  final runtime = _buildRuntime(events, infoLogs: infoLogs);
  final environment = BootstrapEnvironment(
    executableArguments: () => context.rawArgs,
    environment: () => context.rawEnvironment,
    resolveBootstrapContext:
        ({
          required rawArgs,
          required rawEnvironment,
        }) {
          return context;
        },
    ensureWidgetsFlutterBinding: () {
      events.add('binding');
    },
    loadEnvironmentIfNeeded: ({String? logPrefix}) async {
      events.add('env');
      return const EnvironmentLoadOutcome(
        source: EnvironmentSource.bundledAsset,
        sourceDescription: 'test',
        loadedKeyCount: 1,
        missingRequiredKeys: <String>{},
        attemptedFallback: false,
        dotenvInitialized: true,
      );
    },
    resolveBootstrapConfig: ({required rawArgs}) {
      events.add('config');
      return resolvedBootstrapConfig;
    },
    applyBootstrapConfig: (config) {
      events.add('apply_config');
      setAppMode(config.appMode);
    },
    setupServiceLocator: () async {
      events.add('di');
    },
  );

  final uiServices = UiBootstrapServices(
    checkSingleInstance: (bootstrapContext) async {
      events.add('single_instance');
      return canContinueAfterSingleInstanceCheck;
    },
    checkOsCompatibility: () {
      events.add('os');
    },
    initializeApp: ({required appMode}) async {
      events.add('app_init:${appMode.name}');
    },
    getLaunchConfig: ({required bootstrapContext}) async {
      events.add('launch_config');
      return resolvedLaunchConfig;
    },
    executeScheduledBackupAndExit: (scheduleId) async {
      events.add('scheduled:$scheduleId');
    },
    initializeUiServices:
        ({
          required launchConfig,
          required bootstrapConfig,
        }) async {
          events.add('ui_services');
        },
    localSchedulerStartupTask: UiSchedulerStartupTask(
      isTaskSchedulerEnabled: () => true,
      shouldSkipScheduler: (fallbackMode) async {
        events.add('scheduler_policy:${fallbackMode.name}');
        return shouldSkipScheduler;
      },
      startScheduler: () async {
        events.add('scheduler_start');
      },
      logInfo: _ignoreLog,
      logWarning: _ignoreLogWithError,
      logError: _ignoreLogWithError,
    ),
    socketServerStartupTask: SocketServerStartupTask(
      initializeExecutionQueue: () async {
        events.add('queue_init');
      },
      isSocketServerRunning: () => false,
      socketServerPort: () => 9527,
      cleanupExpiredFileTransferLocks: () async {
        events.add('cleanup_locks');
      },
      startSocketServer: () async {
        events.add('socket_start');
      },
      startRemoteStagingCleanup: () async {
        events.add('staging_start');
      },
      logInfo: _ignoreLog,
      logError: _ignoreLogWithError,
    ),
    temporaryBackupCleanupStartupTask: TemporaryBackupCleanupStartupTask(
      isSchedulerRegistered: () => true,
      startScheduler: () {
        events.add('temp_cleanup_start');
      },
      logWarning: _ignoreLogWithError,
    ),
  );

  return AppBootstrapDependencies(
    environment: environment,
    uiServices: uiServices,
    runtime: runtime,
  );
}

BootstrapRuntimeHooks _buildRuntime(
  List<String> events, {
  List<String>? infoLogs,
}) {
  final logLines = infoLogs ?? <String>[];
  return BootstrapRuntimeHooks(
    initializeServiceMode: () async {
      events.add('service_init');
    },
    errorPolicy: BootstrapErrorPolicy(
      logDebug: _ignoreLog,
      logError: _ignoreLogWithError,
      cleanupApp: () async {
        events.add('cleanup');
      },
      exitProcess: (code) {
        events.add('exit:$code');
      },
    ),
    runApp: (app) {
      expect(app, isA<SizedBox>());
      events.add('run_app');
    },
    createApp: () => const SizedBox.shrink(),
    logInfo: logLines.add,
    logWarning: _ignoreLogWithError,
    logError: _ignoreLogWithError,
    logDebug: _ignoreLog,
  );
}

BootstrapConfig _bootstrapConfig({
  AppMode appMode = AppMode.server,
  bool singleInstanceEnabled = true,
  SingleInstanceLockFallbackMode lockFallbackMode =
      SingleInstanceLockFallbackMode.failSafe,
  UiSchedulerFallbackMode schedulerFallbackMode =
      UiSchedulerFallbackMode.failOpen,
}) {
  return BootstrapConfig(
    appMode: appMode,
    singleInstanceEnabled: singleInstanceEnabled,
    uiSingleInstanceLockFallbackMode: lockFallbackMode,
    uiSchedulerFallbackMode: schedulerFallbackMode,
  );
}

LaunchBootstrapContext _uiContext({List<String> args = const <String>[]}) {
  return LaunchBootstrapContext(
    launchOrigin: LaunchOrigin.manual,
    isServiceMode: false,
    processRole: ProcessRole.ui,
    rawArgs: args,
    rawEnvironment: const <String, String>{},
    startMinimizedFromArgs: false,
    usesLegacyWindowsStartupAlias: false,
  );
}

LaunchBootstrapContext _serviceContext() {
  return const LaunchBootstrapContext(
    launchOrigin: LaunchOrigin.serviceControlManager,
    isServiceMode: true,
    processRole: ProcessRole.service,
    rawArgs: <String>['--service'],
    rawEnvironment: <String, String>{'SERVICE_MODE': '1'},
    startMinimizedFromArgs: false,
    usesLegacyWindowsStartupAlias: false,
  );
}
