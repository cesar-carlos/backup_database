import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/application/services/initial_setup_service.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppInitializer {
  static Future<void> initialize() async {
    await _loadEnvironment();
    await _initializeDefaultCredential();
    await _initializeAuthProviders();
    await _initializeAutoUpdate();
  }

  static Future<void> _initializeDefaultCredential() async {
    try {
      final initialSetup = service_locator.getIt<InitialSetupService>();
      final result = await initialSetup.createDefaultCredentialIfNotExists();
      if (result != null) {
        LoggerService.info(
          'Credencial padrao criada (Server ID: ${result.serverId})',
        );
      }
    } on Object catch (e) {
      LoggerService.warning('Erro ao criar credencial padrao: $e');
    }
  }

  static Future<void> _loadEnvironment() async {
    if (dotenv.isInitialized) {
      LoggerService.debug('Variaveis de ambiente ja carregadas');
      return;
    }

    await dotenv.load();
    LoggerService.info('Variaveis de ambiente carregadas');
  }

  static Future<void> _initializeAuthProviders() async {
    try {
      final googleAuthProvider = service_locator.getIt<GoogleAuthProvider>();
      await googleAuthProvider.initialize();
      LoggerService.info('GoogleAuthProvider inicializado');
    } on Object catch (e) {
      LoggerService.warning('Erro ao inicializar GoogleAuthProvider: $e');
    }

    try {
      final dropboxAuthProvider = service_locator.getIt<DropboxAuthProvider>();
      await dropboxAuthProvider.initialize();
    } on Object catch (e) {
      LoggerService.debug('Erro ao inicializar DropboxAuthProvider: $e');
    }
  }

  static Future<void> _initializeAutoUpdate() async {
    try {
      final features = service_locator.getIt<FeatureAvailabilityService>();
      if (!features.isAutoUpdateEnabled) {
        LoggerService.info(
          'AutoUpdateService omitido (compatibilidade): '
          '${features.autoUpdateDisabledReason?.diagnosticLabel ?? "unknown"}',
        );
        return;
      }
      final autoUpdateService = service_locator.getIt<AutoUpdateService>();
      final feedUrl = dotenv.env['AUTO_UPDATE_FEED_URL'];
      await autoUpdateService.initialize(feedUrl);
      LoggerService.info('AutoUpdateService inicializado');
    } on Object catch (e) {
      LoggerService.warning('Erro ao inicializar AutoUpdateService: $e');
    }
  }

  static Future<LaunchConfig> getLaunchConfig({
    required LaunchBootstrapContext bootstrapContext,
  }) async {
    final startMinimizedFromSettings = await service_locator
        .getIt<IMachineSettingsRepository>()
        .getStartMinimized();
    LoggerService.info(
      'Configuração "Iniciar minimizado" carregada: '
      '$startMinimizedFromSettings',
    );

    final args = bootstrapContext.rawArgs;
    final startMinimizedFromArgs = bootstrapContext.startMinimizedFromArgs;
    LoggerService.info(
      'Argumentos de linha de comando (via bootstrapContext): $args '
      '(${SingleInstanceConfig.minimizedArgument}: $startMinimizedFromArgs)',
    );

    final scheduleId = _getScheduleIdFromArgs(args);
    final startMinimized = startMinimizedFromArgs || startMinimizedFromSettings;

    LoggerService.info(
      'Iniciar minimizado: $startMinimized '
      '(configuração: $startMinimizedFromSettings, argumento: '
      '$startMinimizedFromArgs)',
    );

    return LaunchConfig(
      scheduleId: scheduleId,
      startMinimized: startMinimized,
      args: args,
    );
  }

  static String? _getScheduleIdFromArgs(List<String> args) {
    for (final arg in args) {
      if (arg.startsWith('--schedule-id=')) {
        return arg.substring('--schedule-id='.length);
      }
    }
    return null;
  }
}

class LaunchConfig {
  const LaunchConfig({
    required this.scheduleId,
    required this.startMinimized,
    required this.args,
  });

  final String? scheduleId;
  final bool startMinimized;
  final List<String> args;
}
