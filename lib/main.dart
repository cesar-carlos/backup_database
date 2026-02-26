import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/infrastructure/external/system/os_version_checker.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/presentation/app_widget.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/boot/app_initializer.dart';
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

Future<void> _runApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (ServiceModeDetector.isServiceMode()) {
    LoggerService.info('Modo Servico detectado - inicializando sem UI');
    await ServiceModeInitializer.initialize();
    return;
  }

  await _loadEnvironment();
  setAppMode(getAppMode(Platform.executableArguments));
  LoggerService.info('Modo do aplicativo: ${currentAppMode.name}');

  await service_locator.setupServiceLocator();
  _checkOsCompatibility();

  if (SingleInstanceConfig.isEnabled) {
    final canContinue =
        await SingleInstanceChecker.checkAndHandleSecondInstance();
    if (!canContinue) {
      return;
    }

    final canContinueIpc =
        await SingleInstanceChecker.checkIpcServerAndHandle();
    if (!canContinueIpc) {
      return;
    }
  } else {
    LoggerService.info(
      'Single instance check desabilitado via configuração',
    );
  }

  try {
    await AppInitializer.initialize();

    final launchConfig = await AppInitializer.getLaunchConfig();

    if (launchConfig.scheduleId != null) {
      await ScheduledBackupExecutor.executeAndExit(launchConfig.scheduleId!);
      return;
    }

    await _initializeAppServices(launchConfig);

    runApp(const BackupDatabaseApp());

    await _startScheduler();
    await _startSocketServer();
  } on Object catch (e, stackTrace) {
    LoggerService.error('Erro fatal na inicializacao', e, stackTrace);
    await AppCleanup.cleanup();
    exit(1);
  }
}

Future<void> _loadEnvironment() async {
  try {
    await dotenv.load();
    LoggerService.info('Variaveis de ambiente carregadas');
  } on Object catch (e) {
    LoggerService.warning('Nao foi possivel carregar .env: $e');
  }
}

void _checkOsCompatibility() {
  if (!OsVersionChecker.isCompatible()) {
    LoggerService.warning(
      'Sistema operacional pode nao ser compativel. Requisito: Windows 8.1 (6.3) / Server 2012 R2 ou superior.',
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
  final windowManager = WindowManagerService();
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

  if (SingleInstanceConfig.isEnabled) {
    try {
      final singleInstanceService = service_locator
          .getIt<ISingleInstanceService>();
      await singleInstanceService.startIpcServer(
        onShowWindow: () async {
          LoggerService.info(
            'Recebido comando SHOW_WINDOW via IPC de outra instancia',
          );
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
      if (ServiceModeDetector.isServiceMode()) {
        LoggerService.debug('IPC Server nao disponivel em modo servico');
      } else {
        LoggerService.warning('Erro ao inicializar IPC Server: $e');
      }
    }
  } else {
    LoggerService.info(
      'IPC Server não iniciado: single instance desabilitado via configuração',
    );
  }

  final trayManager = TrayManagerService();
  try {
    await trayManager.initialize(onMenuAction: TrayMenuHandler.handleAction);
  } on Object catch (e) {
    if (ServiceModeDetector.isServiceMode()) {
      LoggerService.debug('Tray Manager nao disponivel em modo servico');
    } else {
      LoggerService.warning('Erro ao inicializar tray manager: $e');
    }
  }

  windowManager.setCallbacks(
    onClose: () async {
      await AppCleanup.cleanup();
      exit(0);
    },
  );
}

Future<void> _startScheduler() async {
  try {
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
        'Scheduler local não iniciado: serviço do Windows em execução',
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
  if (error.toString().contains('physicalKey is already pressed')) {
    return;
  }
  LoggerService.error('Erro nao tratado na UI', error, stack);
}

UiSchedulerFallbackMode _getUiSchedulerFallbackModeFromEnv() {
  final normalized = dotenv.env['UI_SCHEDULER_FALLBACK_MODE']
      ?.trim()
      .toLowerCase();

  if (normalized == 'fail_safe') {
    return UiSchedulerFallbackMode.failSafe;
  }

  return UiSchedulerFallbackMode.failOpen;
}
