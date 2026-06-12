import 'dart:async';

import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/app_mode_policy.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/routes/app_router.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/widgets/backup/global_backup_progress_listener.dart';
import 'package:backup_database/presentation/widgets/boot/r1_multi_profile_legacy_hint_host.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart' show SingleChildWidget;

/// Builds the `MultiProvider` tree gated by [AppMode].
///
/// §audit-2026-05-28 (P2): antes registrávamos providers server-only
/// (SchedulerProvider, LogProvider, NotificationProvider, configs SGBD
/// locais, WindowsServiceProvider, ConnectedClientProvider,
/// ServerCredentialProvider) também em modo cliente, e providers
/// client-only (RemoteSchedules, RemoteDatabaseConfig,
/// RemoteFileTransfer, ServerConnection) também em modo servidor.
/// Os providers são lazy no `getIt` (não causavam I/O
/// imediato), mas:
///   - poluíam o DI graph e a leitura do código;
///   - permitiam uso acidental via `context.read<...>()` em rotas que
///     o usuário não deveria acessar naquele modo;
///   - mascaravam dependências que deveriam ser visíveis.
/// Agora cada lista é construída condicionalmente.
class BackupDatabaseApp extends StatelessWidget {
  const BackupDatabaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isClient = AppModePolicy.isClient;
    final isServer = AppModePolicy.isServer;
    final isUnified = !isClient && !isServer;

    return MultiProvider(
      providers: [
        ..._commonProviders(),
        if (isServer || isUnified) ..._serverOnlyProviders(),
        if (isClient || isUnified) ..._clientOnlyProviders(),
      ],
      child: Consumer2<ThemeProvider, AppDensityProvider>(
        builder: (context, themeProvider, densityProvider, _) {
          final density = densityProvider.density;
          final accent = themeProvider.fluentAccentColor;
          return FluentApp.router(
            title: getWindowTitleForMode(currentAppMode),
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightFluentTheme.copyWith(accentColor: accent),
            darkTheme: AppTheme.darkFluentTheme.copyWith(accentColor: accent),
            themeMode: themeProvider.isDarkMode
                ? ThemeMode.dark
                : ThemeMode.light,
            routerConfig: appRouter,
            builder: (context, child) {
              return InheritedAppDensity(
                density: density,
                child: R1MultiProfileLegacyHintHost(
                  child: GlobalBackupProgressListener(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Providers que existem em **todos** os modos (UI core,
  /// preferências, dashboard, licença, auto-update, BackupProgress —
  /// este último é usado pelo `GlobalBackupProgressListener` global
  /// e pelo readiness check de auto-update).
  List<SingleChildWidget> _commonProviders() {
    return [
      ChangeNotifierProvider(
        create: (_) {
          final provider = AppDensityProvider(
            userPreferencesRepository: service_locator
                .getIt<IUserPreferencesRepository>(),
          );
          unawaited(provider.initialize());
          return provider;
        },
      ),
      ChangeNotifierProvider(
        create: (_) {
          final provider = ThemeProvider(
            userPreferencesRepository: service_locator
                .getIt<IUserPreferencesRepository>(),
          );
          unawaited(provider.initialize());
          return provider;
        },
      ),
      ChangeNotifierProvider(
        create: (_) {
          final provider = SkeletonLoadingPreferenceProvider(
            userPreferencesRepository: service_locator
                .getIt<IUserPreferencesRepository>(),
          );
          unawaited(provider.initialize());
          return provider;
        },
      ),
      ChangeNotifierProvider(
        create: (_) {
          final provider = SystemSettingsProvider(
            machineSettingsRepository: service_locator
                .getIt<IMachineSettingsRepository>(),
            userPreferencesRepository: service_locator
                .getIt<IUserPreferencesRepository>(),
            windowsMachineStartupService: service_locator
                .getIt<IWindowsMachineStartupService>(),
            windowManager: WindowManagerService(),
          );
          unawaited(provider.initialize());
          return provider;
        },
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
        create: (_) => service_locator.getIt<ConnectionLogProvider>(),
      ),
    ];
  }

  /// Providers que só fazem sentido com socket server local, scheduler
  /// local e configs SGBD locais. **Não** são montados em modo
  /// cliente — cliente só consome dados do servidor via socket.
  ///
  /// `SqlServerConfigProvider`, `SybaseConfigProvider`,
  /// `PostgresConfigProvider`, `FirebirdConfigProvider` continuam aqui
  /// porque a página `DatabaseConfigPage` é exposta apenas em modo
  /// server/unified (rota bloqueada em client por
  /// `AppModePolicy._clientBlockedRoutes`).
  List<SingleChildWidget> _serverOnlyProviders() {
    return [
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
        create: (_) => service_locator.getIt<FirebirdConfigProvider>(),
      ),
      ChangeNotifierProvider(
        create: (_) => service_locator.getIt<WindowsServiceProvider>(),
      ),
      ChangeNotifierProvider(
        create: (_) => service_locator.getIt<ConnectedClientProvider>(),
      ),
      ChangeNotifierProvider(
        create: (_) => service_locator.getIt<ServerCredentialProvider>(),
      ),
    ];
  }

  @visibleForTesting
  List<SingleChildWidget> debugCommonProviders() => _commonProviders();

  @visibleForTesting
  List<SingleChildWidget> debugServerOnlyProviders() => _serverOnlyProviders();

  @visibleForTesting
  List<SingleChildWidget> debugClientOnlyProviders() => _clientOnlyProviders();

  @visibleForTesting
  List<SingleChildWidget> debugProvidersForServerMode() => [
    ..._commonProviders(),
    ..._serverOnlyProviders(),
  ];

  /// Providers que só fazem sentido para conectar a um servidor
  /// remoto. **Não** são montados em modo servidor — server não conecta
  /// em outros servers.
  List<SingleChildWidget> _clientOnlyProviders() {
    return [
      ChangeNotifierProvider(
        create: (_) => service_locator.getIt<RemoteSchedulesProvider>(),
      ),
      ChangeNotifierProvider(
        create: (_) => service_locator.getIt<RemoteDatabaseConfigProvider>(),
      ),
      ChangeNotifierProvider(
        create: (_) => service_locator.getIt<RemoteFileTransferProvider>(),
      ),
      ChangeNotifierProvider(
        create: (_) => service_locator.getIt<ServerConnectionProvider>(),
      ),
    ];
  }
}
