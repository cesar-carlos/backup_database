import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/config/environment_loader.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/platform/os_version_checker.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/domain/services/i_execution_queue_bootstrap.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/domain/services/i_remote_staging_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_socket_server_lifecycle.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/presentation/app_widget.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/boot/app_initializer.dart';
import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';
import 'package:backup_database/presentation/boot/scheduled_backup_executor.dart';
import 'package:backup_database/presentation/boot/service_mode_initializer.dart';
import 'package:backup_database/presentation/boot/single_instance_checker.dart';
import 'package:backup_database/presentation/boot/socket_server_startup_task.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_startup_task.dart';
import 'package:backup_database/presentation/boot/windows_native_chrome_bootstrap.dart';
import 'package:backup_database/presentation/handlers/tray_menu_handler.dart';
import 'package:backup_database/presentation/managers/managers.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

typedef LaunchBootstrapContextResolverFn =
    LaunchBootstrapContext Function({
      required List<String> rawArgs,
      required Map<String, String> rawEnvironment,
    });
typedef LoadEnvironmentFn = Future<void> Function({String? logPrefix});
typedef ResolveBootstrapConfigFn =
    BootstrapConfig Function({
      required List<String> rawArgs,
    });
typedef InitializeAppFn =
    Future<void> Function({
      required AppMode appMode,
    });
typedef GetLaunchConfigFn =
    Future<LaunchConfig> Function({
      required LaunchBootstrapContext bootstrapContext,
    });
typedef InitializeUiServicesFn =
    Future<void> Function({
      required LaunchConfig launchConfig,
      required BootstrapConfig bootstrapConfig,
    });

class BootstrapEnvironment {
  const BootstrapEnvironment({
    required this.executableArguments,
    required this.environment,
    required this.resolveBootstrapContext,
    required this.ensureWidgetsFlutterBinding,
    required this.loadEnvironmentIfNeeded,
    required this.resolveBootstrapConfig,
    required this.applyBootstrapConfig,
    required this.setupServiceLocator,
  });

  final List<String> Function() executableArguments;
  final Map<String, String> Function() environment;
  final LaunchBootstrapContextResolverFn resolveBootstrapContext;
  final void Function() ensureWidgetsFlutterBinding;
  final LoadEnvironmentFn loadEnvironmentIfNeeded;
  final ResolveBootstrapConfigFn resolveBootstrapConfig;
  final void Function(BootstrapConfig config) applyBootstrapConfig;
  final Future<void> Function() setupServiceLocator;

  BootstrapEnvironment copyWith({
    List<String> Function()? executableArguments,
    Map<String, String> Function()? environment,
    LaunchBootstrapContextResolverFn? resolveBootstrapContext,
    void Function()? ensureWidgetsFlutterBinding,
    LoadEnvironmentFn? loadEnvironmentIfNeeded,
    ResolveBootstrapConfigFn? resolveBootstrapConfig,
    void Function(BootstrapConfig config)? applyBootstrapConfig,
    Future<void> Function()? setupServiceLocator,
  }) {
    return BootstrapEnvironment(
      executableArguments: executableArguments ?? this.executableArguments,
      environment: environment ?? this.environment,
      resolveBootstrapContext:
          resolveBootstrapContext ?? this.resolveBootstrapContext,
      ensureWidgetsFlutterBinding:
          ensureWidgetsFlutterBinding ?? this.ensureWidgetsFlutterBinding,
      loadEnvironmentIfNeeded:
          loadEnvironmentIfNeeded ?? this.loadEnvironmentIfNeeded,
      resolveBootstrapConfig:
          resolveBootstrapConfig ?? this.resolveBootstrapConfig,
      applyBootstrapConfig: applyBootstrapConfig ?? this.applyBootstrapConfig,
      setupServiceLocator: setupServiceLocator ?? this.setupServiceLocator,
    );
  }
}

class UiBootstrapServices {
  const UiBootstrapServices({
    required this.checkSingleInstance,
    required this.checkOsCompatibility,
    required this.initializeApp,
    required this.getLaunchConfig,
    required this.executeScheduledBackupAndExit,
    required this.initializeUiServices,
    required this.localSchedulerStartupTask,
    required this.socketServerStartupTask,
  });

  final Future<bool> Function(LaunchBootstrapContext bootstrapContext)
  checkSingleInstance;
  final void Function() checkOsCompatibility;
  final InitializeAppFn initializeApp;
  final GetLaunchConfigFn getLaunchConfig;
  final Future<void> Function(String scheduleId) executeScheduledBackupAndExit;
  final InitializeUiServicesFn initializeUiServices;
  final UiSchedulerStartupTask localSchedulerStartupTask;
  final SocketServerStartupTask socketServerStartupTask;

  UiBootstrapServices copyWith({
    Future<bool> Function(LaunchBootstrapContext bootstrapContext)?
    checkSingleInstance,
    void Function()? checkOsCompatibility,
    InitializeAppFn? initializeApp,
    GetLaunchConfigFn? getLaunchConfig,
    Future<void> Function(String scheduleId)? executeScheduledBackupAndExit,
    InitializeUiServicesFn? initializeUiServices,
    UiSchedulerStartupTask? localSchedulerStartupTask,
    SocketServerStartupTask? socketServerStartupTask,
  }) {
    return UiBootstrapServices(
      checkSingleInstance: checkSingleInstance ?? this.checkSingleInstance,
      checkOsCompatibility: checkOsCompatibility ?? this.checkOsCompatibility,
      initializeApp: initializeApp ?? this.initializeApp,
      getLaunchConfig: getLaunchConfig ?? this.getLaunchConfig,
      executeScheduledBackupAndExit:
          executeScheduledBackupAndExit ?? this.executeScheduledBackupAndExit,
      initializeUiServices: initializeUiServices ?? this.initializeUiServices,
      localSchedulerStartupTask:
          localSchedulerStartupTask ?? this.localSchedulerStartupTask,
      socketServerStartupTask:
          socketServerStartupTask ?? this.socketServerStartupTask,
    );
  }
}

class BootstrapRuntimeHooks {
  const BootstrapRuntimeHooks({
    required this.initializeServiceMode,
    required this.errorPolicy,
    required this.runApp,
    required this.createApp,
    required this.logInfo,
    required this.logWarning,
    required this.logError,
    required this.logDebug,
  });

  final Future<void> Function() initializeServiceMode;
  final BootstrapErrorPolicy errorPolicy;
  final void Function(Widget app) runApp;
  final Widget Function() createApp;
  final BootstrapLog logInfo;
  final BootstrapLogWithError logWarning;
  final BootstrapLogWithError logError;
  final BootstrapLog logDebug;

  BootstrapRuntimeHooks copyWith({
    Future<void> Function()? initializeServiceMode,
    BootstrapErrorPolicy? errorPolicy,
    void Function(Widget app)? runApp,
    Widget Function()? createApp,
    BootstrapLog? logInfo,
    BootstrapLogWithError? logWarning,
    BootstrapLogWithError? logError,
    BootstrapLog? logDebug,
  }) {
    return BootstrapRuntimeHooks(
      initializeServiceMode:
          initializeServiceMode ?? this.initializeServiceMode,
      errorPolicy: errorPolicy ?? this.errorPolicy,
      runApp: runApp ?? this.runApp,
      createApp: createApp ?? this.createApp,
      logInfo: logInfo ?? this.logInfo,
      logWarning: logWarning ?? this.logWarning,
      logError: logError ?? this.logError,
      logDebug: logDebug ?? this.logDebug,
    );
  }
}

class AppBootstrapDependencies {
  const AppBootstrapDependencies({
    required this.environment,
    required this.uiServices,
    required this.runtime,
  });

  factory AppBootstrapDependencies.defaults() {
    final runtime = BootstrapRuntimeHooks(
      initializeServiceMode: ServiceModeInitializer.initialize,
      errorPolicy: const BootstrapErrorPolicy(
        logDebug: LoggerService.debug,
        logError: LoggerService.error,
        cleanupApp: AppCleanup.cleanup,
        exitProcess: exit,
      ),
      runApp: fluent.runApp,
      createApp: () => const BackupDatabaseApp(),
      logInfo: LoggerService.info,
      logWarning: LoggerService.warning,
      logError: LoggerService.error,
      logDebug: LoggerService.debug,
    );

    return AppBootstrapDependencies(
      environment: BootstrapEnvironment(
        executableArguments: () => Platform.executableArguments,
        environment: () => Platform.environment,
        resolveBootstrapContext: LaunchBootstrapContextResolver.resolve,
        ensureWidgetsFlutterBinding: WidgetsFlutterBinding.ensureInitialized,
        loadEnvironmentIfNeeded: EnvironmentLoader.loadIfNeeded,
        resolveBootstrapConfig:
            ({
              required rawArgs,
            }) {
              return BootstrapConfigResolver(
                onWarning: LoggerService.warning,
              ).resolve(rawArgs: rawArgs);
            },
        applyBootstrapConfig: (config) {
          setAppMode(config.appMode);
        },
        setupServiceLocator: service_locator.setupServiceLocator,
      ),
      uiServices: UiBootstrapServices(
        checkSingleInstance: AppBootstrap._defaultCheckSingleInstance,
        checkOsCompatibility: AppBootstrap._defaultCheckOsCompatibility,
        initializeApp:
            ({
              required appMode,
            }) async {
              await AppInitializer.initialize(appMode: appMode);
            },
        getLaunchConfig: AppInitializer.getLaunchConfig,
        executeScheduledBackupAndExit: ScheduledBackupExecutor.executeAndExit,
        initializeUiServices: AppBootstrap._defaultInitializeUiServices,
        localSchedulerStartupTask: UiSchedulerStartupTask(
          isTaskSchedulerEnabled: () {
            return service_locator
                .getIt<FeatureAvailabilityService>()
                .isTaskSchedulerEnabled;
          },
          shouldSkipScheduler: (fallbackMode) async {
            final windowsServiceService = service_locator
                .getIt<IWindowsServiceService>();
            final schedulerPolicy = UiSchedulerPolicy(
              windowsServiceService,
              onWarning: LoggerService.warning,
              fallbackMode: fallbackMode,
            );
            return schedulerPolicy.shouldSkipSchedulerInUiMode();
          },
          startScheduler: () async {
            await service_locator.getIt<ISchedulerService>().start();
          },
          logInfo: LoggerService.info,
          logWarning: LoggerService.warning,
          logError: LoggerService.error,
        ),
        socketServerStartupTask: SocketServerStartupTask(
          initializeExecutionQueue: () async {
            await service_locator
                .getIt<IExecutionQueueBootstrap>()
                .initialize();
          },
          isSocketServerRunning: () {
            return service_locator.getIt<ISocketServerLifecycle>().isRunning;
          },
          socketServerPort: () {
            return service_locator.getIt<ISocketServerLifecycle>().port;
          },
          cleanupExpiredFileTransferLocks: () async {
            await service_locator
                .getIt<IFileTransferLockService>()
                .cleanupExpiredLocks();
          },
          startSocketServer: () async {
            await service_locator.getIt<ISocketServerLifecycle>().start();
          },
          startRemoteStagingCleanup: () async {
            service_locator.getIt<IRemoteStagingCleanupScheduler>().start();
          },
          logInfo: LoggerService.info,
          logError: LoggerService.error,
        ),
      ),
      runtime: runtime,
    );
  }

  final BootstrapEnvironment environment;
  final UiBootstrapServices uiServices;
  final BootstrapRuntimeHooks runtime;

  AppBootstrapDependencies copyWith({
    BootstrapEnvironment? environment,
    UiBootstrapServices? uiServices,
    BootstrapRuntimeHooks? runtime,
  }) {
    return AppBootstrapDependencies(
      environment: environment ?? this.environment,
      uiServices: uiServices ?? this.uiServices,
      runtime: runtime ?? this.runtime,
    );
  }
}

class AppBootstrap {
  AppBootstrap({AppBootstrapDependencies? dependencies})
    : _dependencies = dependencies ?? AppBootstrapDependencies.defaults();

  final AppBootstrapDependencies _dependencies;

  static Future<void> run() async {
    await AppBootstrap().start();
  }

  static void handleUnhandledError(Object error, StackTrace stack) {
    AppBootstrapDependencies.defaults().runtime.errorPolicy
        .handleUnhandledUiError(
          error,
          stack,
        );
  }

  @visibleForTesting
  Future<void> start() async {
    final bootstrapWatch = Stopwatch()..start();
    final rawArgs = _dependencies.environment.executableArguments();
    final rawEnvironment = _dependencies.environment.environment();

    _dependencies.runtime.logInfo('[main] args=$rawArgs');
    _dependencies.runtime.logInfo(
      '[main] env: SERVICE_MODE=${rawEnvironment['SERVICE_MODE']}, '
      'SERVICE_NAME=${rawEnvironment['SERVICE_NAME']}, '
      'NSSM_SERVICE=${rawEnvironment['NSSM_SERVICE']}',
    );

    final bootstrapContext = _dependencies.environment.resolveBootstrapContext(
      rawArgs: rawArgs,
      rawEnvironment: rawEnvironment,
    );

    _logBootstrapPhase(bootstrapWatch, 'context_resolved');
    _dependencies.runtime.logInfo(
      '[main] processRole=${bootstrapContext.processRole.name}, '
      'launchOrigin=${bootstrapContext.launchOrigin.name}, '
      'isServiceMode=${bootstrapContext.isServiceMode}, '
      'startMinimizedFromArgs=${bootstrapContext.startMinimizedFromArgs}, '
      'windowsStartupCli=${bootstrapContext.usesLegacyWindowsStartupAlias ? 'legacy_alias' : 'canonical_or_manual'}',
    );

    if (bootstrapContext.isServiceMode) {
      _dependencies.runtime.logInfo(
        '[main] processRole=${bootstrapContext.processRole.name} '
        'bootstrap=service_no_ui_surface',
      );
      await _dependencies.runtime.initializeServiceMode();
      _logBootstrapPhase(bootstrapWatch, 'service_init_done');
      return;
    }

    await _runUiBootstrap(
      bootstrapContext: bootstrapContext,
      bootstrapWatch: bootstrapWatch,
      rawArgs: rawArgs,
    );
  }

  Future<void> _runUiBootstrap({
    required LaunchBootstrapContext bootstrapContext,
    required Stopwatch bootstrapWatch,
    required List<String> rawArgs,
  }) async {
    _dependencies.runtime.logInfo(
      '[main] processRole=${bootstrapContext.processRole.name} '
      'bootstrap=ui_single_instance_mutex=${SingleInstanceConfig.uiMutexName.split(r'\').last}',
    );

    _dependencies.environment.ensureWidgetsFlutterBinding();
    await _dependencies.environment.loadEnvironmentIfNeeded(
      logPrefix: '[main]',
    );

    final bootstrapConfig = _dependencies.environment.resolveBootstrapConfig(
      rawArgs: rawArgs,
    );
    _dependencies.environment.applyBootstrapConfig(bootstrapConfig);
    _dependencies.runtime.logInfo(
      'Modo do aplicativo: ${bootstrapConfig.appMode.name}',
    );

    await _dependencies.environment.setupServiceLocator();
    _logBootstrapPhase(bootstrapWatch, 'service_locator_ready');
    _dependencies.runtime.logInfo(
      '[main] singleInstanceLockFallbackUi='
      '${bootstrapConfig.uiSingleInstanceLockFallbackMode.name}',
    );

    _dependencies.uiServices.checkOsCompatibility();

    if (bootstrapConfig.singleInstanceEnabled) {
      final canContinue = await _dependencies.uiServices.checkSingleInstance(
        bootstrapContext,
      );
      if (!canContinue) {
        return;
      }
      _logBootstrapPhase(bootstrapWatch, 'single_instance_ok');
    } else {
      _dependencies.runtime.logInfo(
        'Single instance check desabilitado via configuracao',
      );
    }

    try {
      await _dependencies.uiServices.initializeApp(
        appMode: bootstrapConfig.appMode,
      );
      _logBootstrapPhase(bootstrapWatch, 'app_initializer_done');

      final launchConfig = await _dependencies.uiServices.getLaunchConfig(
        bootstrapContext: bootstrapContext,
      );
      _logBootstrapPhase(bootstrapWatch, 'launch_config_ready');

      if (launchConfig.scheduleId != null) {
        await _dependencies.uiServices.executeScheduledBackupAndExit(
          launchConfig.scheduleId!,
        );
        return;
      }

      await _dependencies.uiServices.initializeUiServices(
        launchConfig: launchConfig,
        bootstrapConfig: bootstrapConfig,
      );
      await _dependencies.uiServices.localSchedulerStartupTask.start(
        bootstrapConfig,
      );
      await _dependencies.uiServices.socketServerStartupTask.start(
        bootstrapConfig,
      );
      if (service_locator.getIt
          .isRegistered<ITemporaryBackupCleanupScheduler>()) {
        service_locator.getIt<ITemporaryBackupCleanupScheduler>().start();
      }
      _logBootstrapPhase(bootstrapWatch, 'scheduler_and_socket_ready');

      _dependencies.runtime.runApp(_dependencies.runtime.createApp());
      _logBootstrapPhase(bootstrapWatch, 'run_app_called');
      _dependencies.runtime.logInfo(
        '[main] bootstrap_timing total_ms='
        '${bootstrapWatch.elapsedMilliseconds}',
      );
    } on Object catch (e, stackTrace) {
      await _dependencies.runtime.errorPolicy.handleFatalUiBootstrapFailure(
        e,
        stackTrace,
      );
    }
  }

  void _logBootstrapPhase(Stopwatch watch, String phase) {
    _dependencies.runtime.logInfo(
      '[main] bootstrap_timing phase=$phase '
      'elapsed_ms=${watch.elapsedMilliseconds}',
    );
  }

  static Future<bool> _defaultCheckSingleInstance(
    LaunchBootstrapContext bootstrapContext,
  ) async {
    final singleInstanceChecker = SingleInstanceChecker(
      singleInstanceService: service_locator.getIt<ISingleInstanceService>(),
      ipcClient: service_locator.getIt<ISingleInstanceIpcClient>(),
      messageBox: service_locator.getIt<IWindowsMessageBox>(),
      launchOrigin: bootstrapContext.launchOrigin,
    );

    return singleInstanceChecker.checkAndHandleSecondInstance();
  }

  static void _defaultCheckOsCompatibility() {
    if (!OsVersionChecker.isCompatible()) {
      LoggerService.warning(
        'Sistema operacional pode nao ser compativel. Requisito: '
        'Windows 8 (6.2) / Server 2012 ou superior.',
      );
      LoggerService.warning(
        'O aplicativo pode nao funcionar corretamente em versoes mais '
        'antigas do Windows.',
      );
      return;
    }

    final versionInfo = OsVersionChecker.getVersionInfo();
    versionInfo.fold(
      (info) {
        LoggerService.info(
          'Sistema operacional compativel: ${info.versionName} '
          '(${info.majorVersion}.${info.minorVersion})',
        );
      },
      (failure) {
        LoggerService.warning('Nao foi possivel verificar versao do SO');
      },
    );
  }

  static Future<void> _defaultInitializeUiServices({
    required LaunchConfig launchConfig,
    required BootstrapConfig bootstrapConfig,
  }) async {
    final features = service_locator.getIt<FeatureAvailabilityService>();
    final windowManager = WindowManagerService();

    await _initializeWindowManager(
      windowManager,
      features,
      launchConfig,
      bootstrapConfig.appMode,
    );
    await Future.wait([
      _initializeIpcServer(features, bootstrapConfig),
      _initializeTrayManager(features),
    ]);

    windowManager.setCallbacks(
      onClose: () async {
        await AppCleanup.cleanup();
        exit(0);
      },
    );
  }

  static Future<void> _initializeWindowManager(
    WindowManagerService windowManager,
    FeatureAvailabilityService features,
    LaunchConfig launchConfig,
    AppMode appMode,
  ) async {
    if (!features.isWindowManagementEnabled) {
      LoggerService.warning(
        'Window manager omitido (compatibilidade): '
        '${features.windowManagementDisabledReason?.diagnosticLabel ?? "unknown"}',
      );
      return;
    }

    try {
      await windowManager.initialize(
        title: getWindowTitleForMode(appMode),
        startMinimized: launchConfig.startMinimized,
      );
      if (Platform.isWindows) {
        final prefsRepo = service_locator.getIt<IUserPreferencesRepository>();
        final micaOn = await prefsRepo.getUseWindowsMicaBackdrop();
        final isDark = await prefsRepo.getDarkMode();
        await WindowsNativeChromeBootstrap.setBackdrop(
          micaEnabled: micaOn,
          isDark: isDark,
        );
      }
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao inicializar window manager (continuando sem UI): $e',
      );
    }
  }

  static Future<void> _initializeIpcServer(
    FeatureAvailabilityService features,
    BootstrapConfig bootstrapConfig,
  ) async {
    if (!bootstrapConfig.singleInstanceEnabled) {
      LoggerService.info(
        'IPC Server nao iniciado: single instance desabilitado via configuracao',
      );
      return;
    }

    try {
      final singleInstanceService = service_locator
          .getIt<ISingleInstanceService>();
      await singleInstanceService.startIpcServer(
        onShowWindow: () async {
          LoggerService.info(
            'Recebido comando SHOW_WINDOW via IPC de outra instancia',
          );
          if (!features.isWindowManagementEnabled) {
            return;
          }
          try {
            await WindowManagerService().show();
            LoggerService.info('Janela trazida para frente apos comando IPC');
          } on Object catch (e, stackTrace) {
            LoggerService.error(
              'Erro ao mostrar janela via IPC',
              e,
              stackTrace,
            );
          }
        },
      );
      LoggerService.info('IPC Server inicializado e pronto');
    } on Object catch (e) {
      LoggerService.warning('Erro ao inicializar IPC Server: $e');
    }
  }

  static Future<void> _initializeTrayManager(
    FeatureAvailabilityService features,
  ) async {
    if (!features.isTrayEnabled) {
      LoggerService.warning(
        'Tray icon omitido (compatibilidade): '
        '${features.trayDisabledReason?.diagnosticLabel ?? "unknown"}',
      );
      return;
    }

    try {
      await TrayManagerService().initialize(
        onMenuAction: TrayMenuHandler.handleAction,
      );
    } on Object catch (e) {
      LoggerService.warning('Erro ao inicializar tray manager: $e');
    }
  }
}
