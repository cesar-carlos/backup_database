import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/di/service_locator.dart' as service_locator;
import '../../core/theme/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/routes/app_router.dart';
import '../../presentation/providers/system_settings_provider.dart';
import '../../presentation/managers/window_manager_service.dart';
import '../../application/providers/providers.dart';

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
        ChangeNotifierProvider(create: (_) => service_locator.getIt<SchedulerProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<LogProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<NotificationProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<SqlServerConfigProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<SybaseConfigProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<PostgresConfigProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<DestinationProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<BackupProgressProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<DashboardProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<AutoUpdateProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<LicenseProvider>()),
        ChangeNotifierProvider(create: (_) => service_locator.getIt<WindowsServiceProvider>()),
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
