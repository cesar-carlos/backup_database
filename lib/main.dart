import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/core.dart';
import 'core/theme/theme_provider.dart';
import 'infrastructure/external/system/os_version_checker.dart';
import 'presentation/managers/managers.dart';
import 'presentation/providers/system_settings_provider.dart';
import 'application/services/scheduler_service.dart';
import 'application/services/auto_update_service.dart';
import 'domain/repositories/repositories.dart';
import 'application/providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar logger PRIMEIRO (antes de qualquer outro serviço)
  LoggerService.init();

  // Verificar compatibilidade do sistema operacional
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

  // O mutex já foi verificado no C++ antes do Flutter iniciar
  // Se chegou aqui, o C++ já permitiu a execução, então é a primeira instância
  // Mas verificamos novamente como segurança adicional
  final singleInstanceService = SingleInstanceService();

  // Verificar via mutex primeiro (mais confiável)
  final isFirstInstance = await singleInstanceService.checkAndLock();

  if (!isFirstInstance) {
    LoggerService.warning(
      '⚠️ SEGUNDA INSTÂNCIA DETECTADA (Mutex existe). Encerrando imediatamente...',
    );

    // Notificar a instância existente para mostrar a janela
    for (int i = 0; i < 5; i++) {
      final notified = await SingleInstanceService.notifyExistingInstance();
      if (notified) {
        LoggerService.info('Instância existente notificada via IPC');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // ENCERRAR IMEDIATAMENTE - não permitir continuação
    exit(0);
  }

  // Verificar se o IPC server já está rodando (outra instância)
  final isServerRunning = await IpcService.checkServerRunning();

  if (isServerRunning) {
    LoggerService.warning(
      '⚠️ SEGUNDA INSTÂNCIA DETECTADA (IPC server já existe). Encerrando imediatamente...',
    );

    // Notificar a instância existente para mostrar a janela
    for (int i = 0; i < 5; i++) {
      final notified = await SingleInstanceService.notifyExistingInstance();
      if (notified) {
        LoggerService.info('Instância existente notificada via IPC');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // ENCERRAR IMEDIATAMENTE - não permitir continuação
    exit(0);
  }

  LoggerService.info(
    '✅ Primeira instância confirmada - continuando inicialização',
  );

  try {
    // Carregar variáveis de ambiente
    await dotenv.load(fileName: '.env');
    LoggerService.info('Variáveis de ambiente carregadas');

    // Configurar injeção de dependências
    await setupServiceLocator();
    LoggerService.info('Dependências configuradas');

    // Inicializar Google Auth Provider
    try {
      final googleAuthProvider = getIt<GoogleAuthProvider>();
      await googleAuthProvider.initialize();
      LoggerService.info('GoogleAuthProvider inicializado');
    } catch (e) {
      LoggerService.warning('Erro ao inicializar GoogleAuthProvider: $e');
    }

    // Inicializar Auto Update Service
    try {
      final autoUpdateService = getIt<AutoUpdateService>();
      final feedUrl = dotenv.env['AUTO_UPDATE_FEED_URL'];
      await autoUpdateService.initialize(feedUrl);
      LoggerService.info('AutoUpdateService inicializado');
    } catch (e) {
      LoggerService.warning('Erro ao inicializar AutoUpdateService: $e');
    }

    // Carregar configuração "Iniciar Minimizado" do SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final startMinimizedFromSettings =
        prefs.getBool('start_minimized') ?? false;
    LoggerService.info(
      'Configuração "Iniciar Minimizado" carregada: $startMinimizedFromSettings',
    );

    // Verificar argumentos de linha de comando
    final args = Platform.executableArguments;
    final startMinimizedFromArgs = args.contains('--minimized');
    LoggerService.info(
      'Argumentos de linha de comando: $args (--minimized: $startMinimizedFromArgs)',
    );
    final scheduleId = _getScheduleIdFromArgs(args);

    // Se foi chamado com schedule-id, executar apenas o backup e sair
    if (scheduleId != null) {
      await _executeScheduledBackupAndExit(scheduleId);
      return;
    }

    // Usar configuração salva ou argumento de linha de comando
    final startMinimized = startMinimizedFromArgs || startMinimizedFromSettings;
    LoggerService.info(
      'Iniciar minimizado: $startMinimized (configuração: $startMinimizedFromSettings, argumento: $startMinimizedFromArgs)',
    );

    // Inicializar window manager primeiro
    final windowManager = WindowManagerService();
    await windowManager.initialize(startMinimized: startMinimized);

    // Inicializar IPC Server para receber comandos de outras instâncias
    // Agora o window manager já está pronto, então podemos mostrar a janela imediatamente
    try {
      await singleInstanceService.startIpcServer(
        onShowWindow: () async {
          LoggerService.info(
            'Recebido comando SHOW_WINDOW via IPC de outra instância',
          );
          try {
            // Window manager já está inicializado, pode mostrar imediatamente
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
      LoggerService.warning('Erro ao inicializar IPC Server: $e');
    }

    // Inicializar tray manager
    final trayManager = TrayManagerService();
    try {
      await trayManager.initialize(onMenuAction: _handleTrayMenuAction);
    } catch (e) {
      LoggerService.warning('Erro ao inicializar tray manager: $e');
    }

    // Configurar callbacks do window manager
    windowManager.setCallbacks(
      onClose: () async {
        await _cleanup();
        exit(0);
      },
    );

    // Iniciar aplicação
    runApp(const BackupDatabaseApp());

    // Iniciar serviço de agendamento
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
      // O TrayManagerService já chama _restoreWindow() antes de chamar este callback
      // Mas vamos garantir que a janela está visível
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

  // Parar scheduler
  try {
    getIt<SchedulerService>().stop();
  } catch (e) {
    LoggerService.warning('Erro ao parar scheduler: $e');
  }

  // Liberar lock de instância única
  await SingleInstanceService().releaseLock();

  // Destruir tray
  try {
    TrayManagerService().dispose();
  } catch (e) {
    LoggerService.warning('Erro ao destruir tray: $e');
  }

  // Destruir window manager
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

    // Buscar schedules habilitados
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

        // Executar cada schedule
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

  // Mostrar a janela se estiver minimizada
  WindowManagerService().show();

  // Navegar para a página de configurações usando o router global
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
        ChangeNotifierProvider(create: (_) => getIt<DestinationProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<BackupProgressProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<DashboardProvider>()),
        ChangeNotifierProvider(create: (_) => getIt<AutoUpdateProvider>()),
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
