import 'dart:io';

import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/application/services/initial_setup_service.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final autoUpdateService = service_locator.getIt<AutoUpdateService>();
      final feedUrl = dotenv.env['AUTO_UPDATE_FEED_URL'];
      await autoUpdateService.initialize(feedUrl);
      LoggerService.info('AutoUpdateService inicializado');
    } on Object catch (e) {
      LoggerService.warning('Erro ao inicializar AutoUpdateService: $e');
    }
  }

  static Future<LaunchConfig> getLaunchConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final startMinimizedFromSettings =
        prefs.getBool('start_minimized') ?? false;
    LoggerService.info(
      'Configuracao "Iniciar Minimizado" carregada: $startMinimizedFromSettings',
    );

    final args = Platform.executableArguments;
    final startMinimizedFromArgs = args.contains('--minimized');
    LoggerService.info(
      'Argumentos de linha de comando: $args (--minimized: $startMinimizedFromArgs)',
    );

    final scheduleId = _getScheduleIdFromArgs(args);
    final startMinimized = startMinimizedFromArgs || startMinimizedFromSettings;

    LoggerService.info(
      'Iniciar minimizado: $startMinimized (configuracao: $startMinimizedFromSettings, argumento: $startMinimizedFromArgs)',
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
