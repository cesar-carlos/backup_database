import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/core.dart';
import '../../core/di/service_locator.dart' as service_locator;
import '../../application/providers/providers.dart';
import '../../application/services/auto_update_service.dart';

class AppInitializer {
  static Future<void> initialize() async {
    await _loadEnvironment();
    await _setupDependencies();
    await _initializeAuthProviders();
    await _initializeAutoUpdate();
  }

  static Future<void> _loadEnvironment() async {
    await dotenv.load(fileName: '.env');
    LoggerService.info('Variáveis de ambiente carregadas');
  }

  static Future<void> _setupDependencies() async {
    await service_locator.setupServiceLocator();
    LoggerService.info('Dependências configuradas');
  }

  static Future<void> _initializeAuthProviders() async {
    try {
      final googleAuthProvider = service_locator.getIt<GoogleAuthProvider>();
      await googleAuthProvider.initialize();
      LoggerService.info('GoogleAuthProvider inicializado');
    } catch (e) {
      LoggerService.warning('Erro ao inicializar GoogleAuthProvider: $e');
    }

    try {
      final dropboxAuthProvider = service_locator.getIt<DropboxAuthProvider>();
      await dropboxAuthProvider.initialize();
    } catch (e) {
      LoggerService.debug('Erro ao inicializar DropboxAuthProvider: $e');
    }
  }

  static Future<void> _initializeAutoUpdate() async {
    try {
      final autoUpdateService = service_locator.getIt<AutoUpdateService>();
      final feedUrl = dotenv.env['AUTO_UPDATE_FEED_URL'];
      await autoUpdateService.initialize(feedUrl);
      LoggerService.info('AutoUpdateService inicializado');
    } catch (e) {
      LoggerService.warning('Erro ao inicializar AutoUpdateService: $e');
    }
  }

  static Future<LaunchConfig> getLaunchConfig() async {
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
    final startMinimized = startMinimizedFromArgs || startMinimizedFromSettings;

    LoggerService.info(
      'Iniciar minimizado: $startMinimized (configuração: $startMinimizedFromSettings, argumento: $startMinimizedFromArgs)',
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
  final String? scheduleId;
  final bool startMinimized;
  final List<String> args;

  const LaunchConfig({
    required this.scheduleId,
    required this.startMinimized,
    required this.args,
  });
}
