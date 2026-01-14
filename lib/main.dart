import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'core/core.dart';
import 'core/theme/theme_provider.dart';
import 'presentation/managers/managers.dart';
import 'infrastructure/external/system/os_version_checker.dart';
import 'presentation/providers/system_settings_provider.dart';
import 'application/services/auto_update_service.dart';
import 'application/services/scheduler_service.dart';
import 'domain/repositories/repositories.dart';
import 'application/providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LoggerService.init();

  // Verificar se está rodando como serviço do Windows ANTES de qualquer outra verificação
  final isServiceMode = ServiceModeDetector.isServiceMode();

  if (isServiceMode) {
    LoggerService.info('🔧 Modo Serviço detectado - inicializando sem UI');
    await _initializeServiceMode();
    return;
  }

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

  final singleInstanceService = SingleInstanceService();

  final isFirstInstance = await singleInstanceService.checkAndLock();

  if (!isFirstInstance) {
    final currentUser =
        WindowsUserService.getCurrentUsername() ?? 'Desconhecido';

    String? existingUser;
    try {
      existingUser = await IpcService.getExistingInstanceUser();
    } catch (e) {
      LoggerService.debug(
        'Não foi possível obter usuário da instância existente: $e',
      );
    }

    final isDifferentUser = existingUser != null && existingUser != currentUser;
    final couldNotDetermineUser = existingUser == null;

    if (isDifferentUser || couldNotDetermineUser) {
      LoggerService.warning(
        '⚠️ SEGUNDA INSTÂNCIA DETECTADA (Mutex existe). '
        'Usuário atual: $currentUser. '
        '${existingUser != null ? "Instância existente em: $existingUser" : "Não foi possível determinar usuário da instância existente"}',
      );
    } else {
      LoggerService.info(
        '⚠️ SEGUNDA INSTÂNCIA DETECTADA (mesmo usuário). '
        'Usuário: $currentUser. Encerrando silenciosamente.',
      );
    }

    for (int i = 0; i < 5; i++) {
      final notified = await SingleInstanceService.notifyExistingInstance();
      if (notified) {
        LoggerService.info('Instância existente notificada via IPC');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    exit(0);
  }

  final isServerRunning = await IpcService.checkServerRunning();

  if (isServerRunning) {
    final currentUser =
        WindowsUserService.getCurrentUsername() ?? 'Desconhecido';

    String? existingUser;
    try {
      existingUser = await IpcService.getExistingInstanceUser();
    } catch (e) {
      LoggerService.debug(
        'Não foi possível obter usuário da instância existente: $e',
      );
    }

    final isDifferentUser = existingUser != null && existingUser != currentUser;
    final couldNotDetermineUser = existingUser == null;

    if (isDifferentUser || couldNotDetermineUser) {
      LoggerService.warning(
        '⚠️ SEGUNDA INSTÂNCIA DETECTADA (IPC server já existe). '
        'Usuário atual: $currentUser. '
        '${existingUser != null ? "Instância existente em: $existingUser" : "Não foi possível determinar usuário da instância existente"}',
      );
    } else {
      LoggerService.info(
        '⚠️ SEGUNDA INSTÂNCIA DETECTADA (mesmo usuário). '
        'Usuário: $currentUser. Encerrando silenciosamente.',
      );
    }

    for (int i = 0; i < 5; i++) {
      final notified = await SingleInstanceService.notifyExistingInstance();
      if (notified) {
        LoggerService.info('Instância existente notificada via IPC');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    exit(0);
  }

  LoggerService.info(
    '✅ Primeira instância confirmada - continuando inicialização',
  );

  try {
    await dotenv.load(fileName: '.env');
    LoggerService.info('Variáveis de ambiente carregadas');

    await setupServiceLocator();
    LoggerService.info('Dependências configuradas');

    try {
      final googleAuthProvider = getIt<GoogleAuthProvider>();
      await googleAuthProvider.initialize();
      LoggerService.info('GoogleAuthProvider inicializado');
    } catch (e) {
      LoggerService.warning('Erro ao inicializar GoogleAuthProvider: $e');
    }

    try {
      final dropboxAuthProvider = getIt<DropboxAuthProvider>();
      await dropboxAuthProvider.initialize();
    } catch (e) {
      LoggerService.debug('Erro ao inicializar DropboxAuthProvider: $e');
    }

    try {
      final autoUpdateService = getIt<AutoUpdateService>();
      final feedUrl = dotenv.env['AUTO_UPDATE_FEED_URL'];
      await autoUpdateService.initialize(feedUrl);
      LoggerService.info('AutoUpdateService inicializado');
    } catch (e) {
      LoggerService.warning('Erro ao inicializar AutoUpdateService: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final startMinimizedFromSettings = prefs.getBool('start_minimized') ?? true;
    LoggerService.info(
      'Configuração "Iniciar Minimizado" carregada: $startMinimizedFromSettings',
    );

    final args = Platform.executableArguments;
    final startMinimizedFromArgs = args.contains('--minimized');
    LoggerService.info(
      'Argumentos de linha de comando: $args (--minimized: $startMinimizedFromArgs)',
    );
    final scheduleId = _getScheduleIdFromArgs(args);

    if (scheduleId != null) {
      await _executeScheduledBackupAndExit(scheduleId);
      return;
    }

    final startMinimized = startMinimizedFromArgs || startMinimizedFromSettings;
    LoggerService.info(
      'Iniciar minimizado: $startMinimized (configuração: $startMinimizedFromSettings, argumento: $startMinimizedFromArgs)',
    );

    final windowManager = WindowManagerService();
    try {
      await windowManager.initialize(startMinimized: startMinimized);
    } catch (e) {
      LoggerService.warning(
        'Erro ao inicializar window manager (continuando sem UI): $e',
      );
    }

    try {
      await singleInstanceService.startIpcServer(
        onShowWindow: () async {
          LoggerService.info(
            'Recebido comando SHOW_WINDOW via IPC de outra instância',
          );
          try {
            await WindowManagerService().show();
            LoggerService.info('Janela trazida para frente após comando IPC');
          } catch (e, stackTrace) {
            LoggerService.error(
              'Erro ao mostrar janela via IPC',
              e,
              stackTrace,
            );
          }
        },
      );
      LoggerService.info('IPC Server inicializado e pronto');
    } catch (e) {
      if (ServiceModeDetector.isServiceMode()) {
        LoggerService.debug(
          'IPC Server não disponível em modo serviço (normal)',
        );
      } else {
        LoggerService.warning('Erro ao inicializar IPC Server: $e');
      }
    }

    final trayManager = TrayManagerService();
    try {
      await trayManager.initialize(onMenuAction: _handleTrayMenuAction);
    } catch (e) {
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
        await _cleanup();
        exit(0);
      },
    );

    runZonedGuarded(() {
      runApp(const BackupDatabaseApp());
    }, (error, stack) {
      if (error.toString().contains('physicalKey is already pressed')) {
        // Ignore this specific framework bug
        return;
      }
      LoggerService.error('Erro não tratado na UI', error, stack);
    });

    try {
      final schedulerService = getIt<SchedulerService>();
      await schedulerService.start();
      LoggerService.info('Serviço de agendamento iniciado');
    } catch (e) {
      LoggerService.error('Erro ao iniciar scheduler', e);
    }
  } catch (e, stackTrace) {
    LoggerService.error('Erro fatal na inicialização', e, stackTrace);
    await _cleanup();
    exit(1);
  }
}

Future<void> _initializeServiceMode() async {
  try {
    await dotenv.load(fileName: '.env');
    LoggerService.info('Variáveis de ambiente carregadas');

    await setupServiceLocator();
    LoggerService.info('Dependências configuradas');

    try {
      final schedulerService = getIt<SchedulerService>();
      await schedulerService.start();
      LoggerService.info('✅ Serviço de agendamento iniciado em modo serviço');
    } catch (e) {
      LoggerService.error('Erro ao iniciar scheduler em modo serviço', e);
      exit(1);
    }

    LoggerService.info('✅ Aplicativo rodando como serviço do Windows');

    await Future.delayed(const Duration(days: 365));
  } catch (e, stackTrace) {
    LoggerService.error(
      'Erro fatal na inicialização do modo serviço',
      e,
      stackTrace,
    );
    exit(1);
  }
}

String? _getScheduleIdFromArgs(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--schedule-id=')) {
      return arg.substring('--schedule-id='.length);
    }
  }
  return null;
}

Future<void> _executeScheduledBackupAndExit(String scheduleId) async {
  LoggerService.info('Executando backup agendado: $scheduleId');

  try {
    final schedulerService = getIt<SchedulerService>();
    await schedulerService.executeNow(scheduleId);
    LoggerService.info('Backup concluído');
  } catch (e) {
    LoggerService.error('Erro no backup agendado: $e');
  }

  await _cleanup();
  exit(0);
}

void _handleTrayMenuAction(TrayMenuAction action) {
  switch (action) {
    case TrayMenuAction.show:
      WindowManagerService().show();
      break;

    case TrayMenuAction.executeBackup:
      _executeManualBackup();
      break;

    case TrayMenuAction.pauseScheduler:
      getIt<SchedulerService>().stop();
      TrayManagerService().setSchedulerPaused(true);
      break;

    case TrayMenuAction.resumeScheduler:
      getIt<SchedulerService>().start();
      TrayManagerService().setSchedulerPaused(false);
      break;

    case TrayMenuAction.settings:
      _navigateToSettings();
      break;

    case TrayMenuAction.exit:
      _exitApp();
      break;
  }
}

Future<void> _cleanup() async {
  LoggerService.info('Encerrando aplicativo...');

  try {
    getIt<SchedulerService>().stop();
  } catch (e) {
    LoggerService.warning('Erro ao parar scheduler: $e');
  }

  await SingleInstanceService().releaseLock();

  try {
    TrayManagerService().dispose();
  } catch (e) {
    LoggerService.warning('Erro ao destruir tray: $e');
  }

  try {
    WindowManagerService().dispose();
  } catch (e) {
    LoggerService.warning('Erro ao destruir window manager: $e');
  }

  LoggerService.info('Aplicativo encerrado');
}

Future<void> _executeManualBackup() async {
  LoggerService.info('Executar backup manual solicitado via tray');

  try {
    final scheduleRepository = getIt<IScheduleRepository>();
    final schedulerService = getIt<SchedulerService>();

    final schedulesResult = await scheduleRepository.getEnabled();

    await schedulesResult.fold(
      (schedules) async {
        if (schedules.isEmpty) {
          LoggerService.warning('Nenhum agendamento habilitado encontrado');
          return;
        }

        LoggerService.info(
          'Encontrados ${schedules.length} agendamento(s) habilitado(s). Executando...',
        );

        int successCount = 0;
        int failureCount = 0;

        for (final schedule in schedules) {
          LoggerService.info('Executando backup: ${schedule.name}');

          final result = await schedulerService.executeNow(schedule.id);

          result.fold(
            (_) {
              successCount++;
              LoggerService.info(
                'Backup concluído com sucesso: ${schedule.name}',
              );
            },
            (failure) {
              failureCount++;
              LoggerService.error(
                'Erro ao executar backup: ${schedule.name}',
                failure,
              );
            },
          );
        }

        LoggerService.info(
          'Backup manual concluído. Sucesso: $successCount, Falhas: $failureCount',
        );
      },
      (failure) async {
        LoggerService.error('Erro ao buscar agendamentos habilitados', failure);
      },
    );
  } catch (e, stackTrace) {
    LoggerService.error('Erro ao executar backup manual', e, stackTrace);
  }
}

void _navigateToSettings() {
  LoggerService.info('Navegando para configurações via tray menu');

  WindowManagerService().show();

  appRouter.go(RouteNames.settings);
}

void _exitApp() async {
  await _cleanup();
  exit(0);
}

class BackupDatabaseApp extends StatelessWidget {
  const BackupDatabaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final provider = ThemeProvider();
            provider.initialize();
            return provider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final provider = SystemSettingsProvider(
              windowManager: WindowManagerService(),
            );
            provider.initialize();
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => getIt<SchedulerProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<LogProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<NotificationProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<SqlServerConfigProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<SybaseConfigProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<PostgresConfigProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<DestinationProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<BackupProgressProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<DashboardProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<AutoUpdateProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<LicenseProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<WindowsServiceProvider>()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return FluentApp.router(
            title: 'Backup Database',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightFluentTheme,
            darkTheme: AppTheme.darkFluentTheme,
            themeMode: themeProvider.isDarkMode
                ? ThemeMode.dark
                : ThemeMode.light,
            routerConfig: appRouter,
          );
        },
      ),
    );
  }
}
