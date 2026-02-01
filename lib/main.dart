import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/infrastructure/external/system/os_version_checker.dart';
import 'package:backup_database/presentation/app_widget.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/boot/app_initializer.dart';
import 'package:backup_database/presentation/boot/scheduled_backup_executor.dart';
import 'package:backup_database/presentation/boot/service_mode_initializer.dart';
import 'package:backup_database/presentation/boot/single_instance_checker.dart';
import 'package:backup_database/presentation/handlers/tray_menu_handler.dart';
import 'package:backup_database/presentation/managers/managers.dart';
import 'package:fluent_ui/fluent_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LoggerService.init();

  if (ServiceModeDetector.isServiceMode()) {
    LoggerService.info('🔧 Modo Serviço detectado - inicializando sem UI');
    await ServiceModeInitializer.initialize();
    return;
  }

  _checkOsCompatibility();

  final canContinue =
      await SingleInstanceChecker.checkAndHandleSecondInstance();
  if (!canContinue) return;

  final canContinueIpc = await SingleInstanceChecker.checkIpcServerAndHandle();
  if (!canContinueIpc) return;

  LoggerService.info(
    '✅ Primeira instância confirmada - continuando inicialização',
  );

  try {
    await AppInitializer.initialize();

    setAppMode(getAppMode(Platform.executableArguments));
    LoggerService.info('Modo do aplicativo: ${currentAppMode.name}');

    final launchConfig = await AppInitializer.getLaunchConfig();

    if (launchConfig.scheduleId != null) {
      await ScheduledBackupExecutor.executeAndExit(launchConfig.scheduleId!);
      return;
    }

    await _initializeAppServices(launchConfig);

    runZonedGuarded(() => runApp(const BackupDatabaseApp()), _handleError);

    await _startScheduler();
  } on Object catch (e, stackTrace) {
    LoggerService.error('Erro fatal na inicialização', e, stackTrace);
    await AppCleanup.cleanup();
    exit(1);
  }
}

void _checkOsCompatibility() {
  if (!OsVersionChecker.isCompatible()) {
    LoggerService.warning(
      '⚠️ Sistema operacional pode não ser compatível. Requisito: Windows 8.1 (6.3) / Server 2012 R2 ou superior.',
    );
    LoggerService.warning(
      'O aplicativo pode não funcionar corretamente em versões mais antigas do Windows.',
    );
  } else {
    final versionInfo = OsVersionChecker.getVersionInfo();
    versionInfo.fold(
      (info) {
        LoggerService.info(
          '✅ Sistema operacional compatível: ${info.versionName} (${info.majorVersion}.${info.minorVersion})',
        );
      },
      (failure) {
        LoggerService.warning('Não foi possível verificar versão do SO');
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

  try {
    final singleInstanceService = SingleInstanceService();
    await singleInstanceService.startIpcServer(
      onShowWindow: () async {
        LoggerService.info(
          'Recebido comando SHOW_WINDOW via IPC de outra instância',
        );
        try {
          await WindowManagerService().show();
          LoggerService.info('Janela trazida para frente após comando IPC');
        } on Object catch (e, stackTrace) {
          LoggerService.error('Erro ao mostrar janela via IPC', e, stackTrace);
        }
      },
    );
    LoggerService.info('IPC Server inicializado e pronto');
  } on Object catch (e) {
    if (ServiceModeDetector.isServiceMode()) {
      LoggerService.debug('IPC Server não disponível em modo serviço (normal)');
    } else {
      LoggerService.warning('Erro ao inicializar IPC Server: $e');
    }
  }

  final trayManager = TrayManagerService();
  try {
    await trayManager.initialize(onMenuAction: TrayMenuHandler.handleAction);
  } on Object catch (e) {
    if (ServiceModeDetector.isServiceMode()) {
      LoggerService.debug(
        'Tray Manager não disponível em modo serviço (normal)',
      );
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
    final schedulerService = service_locator.getIt<SchedulerService>();
    await schedulerService.start();
    LoggerService.info('Serviço de agendamento iniciado');
  } on Object catch (e) {
    LoggerService.error('Erro ao iniciar scheduler', e);
  }
}

void _handleError(Object error, StackTrace stack) {
  if (error.toString().contains('physicalKey is already pressed')) {
    return;
  }
  LoggerService.error('Erro não tratado na UI', error, stack);
}
