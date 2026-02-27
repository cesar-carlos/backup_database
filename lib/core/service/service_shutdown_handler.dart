import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';

/// Callback para executar durante o shutdown.
///
/// Recebe o timeout máximo permitido para execução.
typedef ShutdownCallback = Future<void> Function(Duration timeout);

/// Handler para gerenciar o encerramento gracioso do serviço.
///
/// Escuta sinais de shutdown (SIGTERM, SIGINT) e executa
/// limpeza apropriada antes de encerrar o processo.
class ServiceShutdownHandler {
  static ServiceShutdownHandler? _instance;

  ServiceShutdownHandler._();

  /// Retorna a instância singleton do ServiceShutdownHandler.
  factory ServiceShutdownHandler() => _instance ??= ServiceShutdownHandler._();

  final List<ShutdownCallback> _shutdownCallbacks = [];
  bool _isShuttingDown = false;
  bool _isInitialized = false;

  /// Inicializa o handler e registra sinais de shutdown.
  Future<void> initialize() async {
    if (_isInitialized) {
      LoggerService.warning('ServiceShutdownHandler já inicializado');
      return;
    }

    if (!Platform.isWindows) {
      LoggerService.info(
        'ServiceShutdownHandler: apenas Windows é suportado',
      );
      return;
    }

    try {
      // Registra handler para SIGINT (Ctrl+C)
      ProcessSignal.sigint.watch().listen((_) {
        LoggerService.info('SIGINT recebido (Ctrl+C)');
        _handleShutdown(const Duration(seconds: 30));
      });

      // Registra handler para SIGTERM
      ProcessSignal.sigterm.watch().listen((_) {
        LoggerService.info('SIGTERM recebido');
        _handleShutdown(const Duration(seconds: 30));
      });

      _isInitialized = true;
      LoggerService.info('✅ ServiceShutdownHandler inicializado');
    } on Object catch (e, s) {
      LoggerService.error('Erro ao inicializar ServiceShutdownHandler', e, s);
    }
  }

  /// Registra um callback para ser executado durante o shutdown.
  ///
  /// Os callbacks são executados na ordem inversa do registro
  /// (último registrado, primeiro executado - stack behavior).
  void registerCallback(ShutdownCallback callback) {
    _shutdownCallbacks.add(callback);
    LoggerService.debug(
      'Shutdown callback registrado. Total: ${_shutdownCallbacks.length}',
    );
  }

  /// Executa o shutdown gracioso manualmente.
  ///
  /// Use este método para encerrar o serviço de forma controlada.
  Future<void> shutdown({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_isShuttingDown) {
      LoggerService.warning('Shutdown já em andamento');
      return;
    }

    await _handleShutdown(timeout);
  }

  Future<void> _handleShutdown(Duration timeout) async {
    if (_isShuttingDown) {
      return;
    }

    _isShuttingDown = true;
    final startTime = DateTime.now();

    LoggerService.info('');
    LoggerService.info('═══════════════════════════════════════');
    LoggerService.info('🛑 INICIANDO SHUTDOWN GRACIOSO');
    LoggerService.info('═══════════════════════════════════════');
    LoggerService.info(
      'Orçamento total: ${timeout.inSeconds}s | '
      'Callbacks: ${_shutdownCallbacks.length}',
    );
    LoggerService.info('');

    var callbacksExecuted = 0;
    var callbacksSkippedByTimeout = 0;

    for (var i = _shutdownCallbacks.length - 1; i >= 0; i--) {
      final callback = _shutdownCallbacks[i];
      final elapsed = DateTime.now().difference(startTime);
      final remaining = timeout - elapsed;

      if (remaining <= Duration.zero) {
        callbacksSkippedByTimeout = _shutdownCallbacks.length - i;
        LoggerService.warning(
          '⚠️ Timeout atingido (orçamento esgotado após ${elapsed.inSeconds}s). '
          'Ignorando $callbacksSkippedByTimeout callback(s) restante(s)',
        );
        break;
      }

      callbacksExecuted++;
      final callbackName = callback.hashCode.toRadixString(16);
      LoggerService.info(
        '[$callbackName] Etapa $callbacksExecuted: orçamento ${remaining.inSeconds}s',
      );

      try {
        final stopwatch = Stopwatch()..start();
        await callback(remaining);
        stopwatch.stop();
        final stillRemaining = timeout - DateTime.now().difference(startTime);

        LoggerService.info(
          '[$callbackName] ✅ Concluído em ${stopwatch.elapsedMilliseconds}ms '
          '(${stillRemaining.inSeconds}s restantes)',
        );
      } on Object catch (e, s) {
        LoggerService.error(
          '[$callbackName] ❌ Erro durante shutdown',
          e,
          s,
        );
      }

      LoggerService.info('');
    }

    final totalElapsed = DateTime.now().difference(startTime);
    LoggerService.info('═══════════════════════════════════════');
    LoggerService.info(
      '✅ SHUTDOWN CONCLUÍDO | '
      'Tempo: ${totalElapsed.inSeconds}s | '
      'Executados: $callbacksExecuted'
      '${callbacksSkippedByTimeout > 0 ? " | Ignorados (timeout): $callbacksSkippedByTimeout" : ""}',
    );
    LoggerService.info('═══════════════════════════════════════');
    LoggerService.info('');
  }

  /// Verifica se o processo está em shutdown.
  bool get isShuttingDown => _isShuttingDown;

  /// Verifica se o handler está inicializado.
  bool get isInitialized => _isInitialized;
}
