import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/routes/app_router.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/core/theme/theme_provider.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:backup_database/presentation/providers/system_settings_provider.dart';
import 'package:backup_database/presentation/widgets/backup/global_backup_progress_listener.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

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
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<SchedulerProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<LogProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<NotificationProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<SqlServerConfigProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<SybaseConfigProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<PostgresConfigProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<DestinationProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<BackupProgressProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<DashboardProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<AutoUpdateProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<LicenseProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<WindowsServiceProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<ConnectedClientProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<ConnectionLogProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<ServerCredentialProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<RemoteSchedulesProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<RemoteFileTransferProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => service_locator.getIt<ServerConnectionProvider>(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return GlobalBackupProgressListener(
            child: FluentApp.router(
              title: getWindowTitleForMode(currentAppMode),
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightFluentTheme,
              darkTheme: AppTheme.darkFluentTheme,
              themeMode: themeProvider.isDarkMode
                  ? ThemeMode.dark
                  : ThemeMode.light,
              routerConfig: appRouter,
            ),
          );
        },
      ),
    );
  }
}
