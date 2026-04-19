import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/config/environment_loader.dart';
import 'package:backup_database/core/config/process_role.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/infrastructure/external/system/os_version_checker.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/presentation/app_widget.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/boot/app_initializer.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';
import 'package:backup_database/presentation/boot/scheduled_backup_executor.dart';
import 'package:backup_database/presentation/boot/service_mode_initializer.dart';
import 'package:backup_database/presentation/boot/single_instance_checker.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';
import 'package:backup_database/presentation/handlers/tray_menu_handler.dart';
import 'package:backup_database/presentation/managers/managers.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  runZonedGuarded(_runApp, _handleError);
}

void _logBootstrapPhase(Stopwatch watch, String phase) {
  LoggerService.info(
    '[main] bootstrap_timing phase=$phase elapsed_ms=${watch.elapsedMilliseconds}',
  );
}

Future<void> _runApp() async {
  final bootstrapWatch = Stopwatch()..start();
  final rawArgs = Platform.executableArguments;

  LoggerService.info('[main] args=$rawArgs');
  LoggerService.info(
    '[main] env: SERVICE_MODE=${Platform.environment['SERVICE_MODE']}, '
    'SERVICE_NAME=${Platform.environment['SERVICE_NAME']}, '
    'NSSM_SERVICE=${Platform.environment['NSSM_SERVICE']}',
  );
  final bootstrapContext = LaunchBootstrapContextResolver.resolve(
    rawArgs: rawArgs,
    rawEnvironment: Platform.environment,
  );
  _logBootstrapPhase(bootstrapWatch, 'context_resolved');
  LoggerService.info(
    '[main] processRole=${bootstrapContext.processRole.name}, '
    'launchOrigin=${bootstrapContext.launchOrigin.name}, '
    'isServiceMode=${bootstrapContext.isServiceMode}, '
    'startMinimizedFromArgs=${bootstrapContext.startMinimizedFromArgs}, '
    'windowsStartupCli=${bootstrapContext.usesLegacyWindowsStartupAlias ? 'legacy_alias' : 'canonical_or_manual'}',
  );

  // Verifica modo serviço ANTES de inicializar Flutter binding
  // para evitar tentar criar rendering surface em Session 0
  if (bootstrapContext.isServiceMode) {
    LoggerService.info(
      '[main] processRole=${ProcessRole.service.name} '
      'bootstrap=service_no_ui_surface',
    );
    await ServiceModeInitializer.initialize();
    _logBootstrapPhase(bootstrapWatch, 'service_init_done');
    return;
  }

  // Só inicializa Flutter binding se não estiver em modo serviço
  LoggerService.info(
    '[main] processRole=${ProcessRole.ui.name} '
    'bootstrap=ui_single_instance_mutex=${SingleInstanceConfig.uiMutexName.split(r'\').last}',
  );
  WidgetsFlutterBinding.ensureInitialized();

  await EnvironmentLoader.loadIfNeeded(logPrefix: '[main]');
  setAppMode(getAppMode(rawArgs));
  LoggerService.info('Modo do aplicativo: ${currentAppMode.name}');

  // `setupServiceLocator` agora também invoca `registerFeatureAvailability`
  // internamente (movido para dentro de DI). Antes ficava como chamada
  // solta aqui, fora da camada de DI.
  await service_locator.setupServiceLocator();
  _logBootstrapPhase(bootstrapWatch, 'service_locator_ready');
  LoggerService.info(
    '[main] singleInstanceLockFallbackUi=${SingleInstanceConfig.lockFallbackMode.name}',
  );
  _checkOsCompatibility();

  if (SingleInstanceConfig.isEnabled) {
    final singleInstanceChecker = SingleInstanceChecker(
      singleInstanceService: service_locator.getIt<ISingleInstanceService>(),
      ipcClient: service_locator.getIt<ISingleInstanceIpcClient>(),
      messageBox: service_locator.getIt<IWindowsMessageBox>(),
      launchOrigin: bootstrapContext.launchOrigin,
    );

    final canContinue = await singleInstanceChecker
        .checkAndHandleSecondInstance();
    if (!canContinue) {
      return;
    }
    _logBootstrapPhase(bootstrapWatch, 'single_instance_ok');
  } else {
    LoggerService.info(
      'Single instance check desabilitado via configuração',
    );
  }

  try {
    await AppInitializer.initialize();
    _logBootstrapPhase(bootstrapWatch, 'app_initializer_done');

    final launchConfig = await AppInitializer.getLaunchConfig(
      bootstrapContext: bootstrapContext,
    );
    _logBootstrapPhase(bootstrapWatch, 'launch_config_ready');

    if (launchConfig.scheduleId != null) {
      await ScheduledBackupExecutor.executeAndExit(launchConfig.scheduleId!);
      return;
    }

    await _initializeAppServices(launchConfig);

    // Inicia o scheduler e o socket server ANTES do `runApp` para evitar
    // race entre cliques iniciais do usuário ("Executar agora") e o
    // scheduler ainda não inicializado. `runApp` é a última coisa porque
    // bloqueia o evento loop do Flutter.
    await _startScheduler();
    await _startSocketServer();
    _logBootstrapPhase(bootstrapWatch, 'scheduler_and_socket_ready');

    runApp(const BackupDatabaseApp());
    _logBootstrapPhase(bootstrapWatch, 'run_app_called');
    LoggerService.info(
      '[main] bootstrap_timing total_ms=${bootstrapWatch.elapsedMilliseconds}',
    );
  } on Object catch (e, stackTrace) {
    LoggerService.error('Erro fatal na inicializacao', e, stackTrace);
    await AppCleanup.cleanup();
    exit(1);
  }
}

void _checkOsCompatibility() {
  if (!OsVersionChecker.isCompatible()) {
    LoggerService.warning(
      'Sistema operacional pode nao ser compativel. Requisito: '
      'Windows 8 (6.2) / Server 2012 ou superior.',
    );
    LoggerService.warning(
      'O aplicativo pode nao funcionar corretamente em versoes mais antigas do Windows.',
    );
  } else {
    final versionInfo = OsVersionChecker.getVersionInfo();
    versionInfo.fold(
      (info) {
        LoggerService.info(
          'Sistema operacional compativel: ${info.versionName} (${info.majorVersion}.${info.minorVersion})',
        );
      },
      (failure) {
        LoggerService.warning('Nao foi possivel verificar versao do SO');
      },
    );
  }
}

Future<void> _initializeAppServices(LaunchConfig launchConfig) async {
  final features = service_locator.getIt<FeatureAvailabilityService>();
  final windowManager = WindowManagerService();

  // Window manager precisa ser o primeiro porque tray/IPC podem depender
  // dele indiretamente (ex.: tray menu mostra a janela). Os dois passos
  // seguintes (IPC server e tray) são independentes entre si — rodam em
  // paralelo.
  await _initializeWindowManager(windowManager, features, launchConfig);

  await Future.wait([
    _initializeIpcServer(features),
    _initializeTrayManager(features),
  ]);

  windowManager.setCallbacks(
    onClose: () async {
      await AppCleanup.cleanup();
      exit(0);
    },
  );
}

Future<void> _initializeWindowManager(
  WindowManagerService windowManager,
  FeatureAvailabilityService features,
  LaunchConfig launchConfig,
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
      title: getWindowTitleForMode(currentAppMode),
      startMinimized: launchConfig.startMinimized,
    );
  } on Object catch (e) {
    LoggerService.warning(
      'Erro ao inicializar window manager (continuando sem UI): $e',
    );
  }
}

Future<void> _initializeIpcServer(FeatureAvailabilityService features) async {
  if (!SingleInstanceConfig.isEnabled) {
    LoggerService.info(
      'IPC Server não iniciado: single instance desabilitado via configuração',
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

Future<void> _initializeTrayManager(FeatureAvailabilityService features) async {
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

Future<void> _startScheduler() async {
  try {
    final features = service_locator.getIt<FeatureAvailabilityService>();
    if (!features.isTaskSchedulerEnabled) {
      LoggerService.warning(
        'Agendamento local nao iniciado: Task Scheduler indisponivel para '
        'esta versao do Windows.',
      );
      return;
    }
    final fallbackMode = _getUiSchedulerFallbackModeFromEnv();
    final windowsServiceService = service_locator
        .getIt<IWindowsServiceService>();
    final schedulerPolicy = UiSchedulerPolicy(
      windowsServiceService,
      onWarning: LoggerService.warning,
      fallbackMode: fallbackMode,
    );
    final shouldSkipScheduler = await schedulerPolicy
        .shouldSkipSchedulerInUiMode();
    if (shouldSkipScheduler) {
      LoggerService.info(
        '[main] processRole=${ProcessRole.ui.name} '
        'scheduler_local_skipped=windows_service_installed_and_running',
      );
      return;
    }

    final schedulerService = service_locator.getIt<ISchedulerService>();
    await schedulerService.start();
    LoggerService.info('Servico de agendamento iniciado');
  } on Object catch (e) {
    LoggerService.error('Erro ao iniciar scheduler', e);
  }
}

Future<void> _startSocketServer() async {
  if (currentAppMode != AppMode.server) {
    LoggerService.info(
      'Modo cliente detectado - socket server nao sera iniciado',
    );
    return;
  }

  try {
    final socketServer = service_locator.getIt<SocketServerService>();

    if (socketServer.isRunning) {
      LoggerService.info(
        'Socket server ja esta rodando na porta ${socketServer.port}',
      );
      return;
    }

    await socketServer.start();
    LoggerService.info(
      'Socket server iniciado automaticamente na porta 9527',
    );
  } on Object catch (e, stackTrace) {
    LoggerService.error('Erro ao iniciar socket server', e, stackTrace);
  }
}

void _handleError(Object error, StackTrace stack) {
  // Workaround conhecido para bug do Flutter Desktop em Windows quando
  // teclas modificadoras são liberadas fora do foco da janela. Se este
  // workaround precisar sair, basta procurar por esta linha no log.
  if (error.toString().contains('physicalKey is already pressed')) {
    LoggerService.debug(
      'Ignorando erro conhecido do Flutter (physicalKey already pressed): '
      '$error',
    );
    return;
  }
  LoggerService.error('Erro nao tratado na UI', error, stack);
}

UiSchedulerFallbackMode _getUiSchedulerFallbackModeFromEnv() {
  final raw = dotenv.env['UI_SCHEDULER_FALLBACK_MODE'];
  final normalized = raw?.trim().toLowerCase();

  if (normalized == null || normalized.isEmpty) {
    return UiSchedulerFallbackMode.failOpen;
  }

  if (normalized == 'fail_safe') return UiSchedulerFallbackMode.failSafe;
  if (normalized == 'fail_open') return UiSchedulerFallbackMode.failOpen;

  // Valores não reconhecidos antes caíam silenciosamente em failOpen,
  // o que mascarava typos como "failsafe" / "safe". Agora avisamos.
  LoggerService.warning(
    '[main] UI_SCHEDULER_FALLBACK_MODE="$raw" não reconhecido. '
    'Valores aceitos: "fail_safe" ou "fail_open". Usando fail_open.',
  );
  return UiSchedulerFallbackMode.failOpen;
}
