import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Callback para executar durante o shutdown.
///
/// Recebe o timeout máximo permitido para execução.
typedef ShutdownCallback = Future<void> Function(Duration timeout);

/// Handler para gerenciar o encerramento gracioso do serviço.
///
/// Escuta sinais de shutdown (SIGTERM, SIGINT) e executa
/// limpeza apropriada antes de encerrar o processo.
///
/// **S9 da auditoria — migração do singleton estático**: anteriormente
/// era um `static ServiceShutdownHandler? _instance` com `factory ()`
/// que devolvia o mesmo objeto. Isso causava 3 problemas:
///   1. Estado persistia entre testes (não havia reset).
///   2. `_isShuttingDown` nunca voltava a `false` — segunda chamada
///      virava no-op silencioso.
///   3. Impossível injetar mock em testes do bootstrap.
///
/// Agora o construtor é público e o handler é registrado como
/// `lazySingleton` no `setupCoreModule`. Para preservar
/// retrocompatibilidade temporária com callers antigos, mantemos um
/// `factory.legacy()` que delega ao mesmo objeto cacheado — **deprecated**,
/// novos callers devem usar `getIt<ServiceShutdownHandler>()`.
class ServiceShutdownHandler {
  ServiceShutdownHandler({
    Stream<ProcessSignal> Function(ProcessSignal)? watchSignal,
  }) : _watchSignal = watchSignal ?? ((signal) => signal.watch());

  final Stream<ProcessSignal> Function(ProcessSignal) _watchSignal;

  /// Orçamento padrão do shutdown gracioso (SIGINT/SIGTERM e
  /// `beforeInstallHook` do auto-update em modo serviço).
  static const Duration defaultGracefulShutdownTimeout = Duration(seconds: 30);

  /// Construtor para callers legados (sem DI). Mantém compatibilidade
  /// com o `factory ServiceShutdownHandler()` original que retornava
  /// um singleton implícito.
  ///
  /// Equivalente a `getIt<ServiceShutdownHandler>()` quando o DI já
  /// está pronto. Use em scripts/tools que rodam fora do bootstrap
  /// completo do app.
  @Deprecated('Use getIt<ServiceShutdownHandler>() ou injete via construtor')
  factory ServiceShutdownHandler.legacy() {
    return _legacyInstance ??= ServiceShutdownHandler();
  }

  static ServiceShutdownHandler? _legacyInstance;

  /// Reseta o singleton legado. Apenas para uso em testes.
  @visibleForTesting
  static void resetLegacyInstanceForTest() {
    _legacyInstance = null;
  }

  final List<ShutdownCallback> _shutdownCallbacks = [];
  final List<void Function()> _completionCallbacks = [];
  final List<void Function()> _startCallbacks = [];
  final List<StreamSubscription<ProcessSignal>> _signalSubscriptions = [];
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
      _signalSubscriptions.add(
        _watchSignal(ProcessSignal.sigint).listen((_) {
          LoggerService.info('SIGINT recebido (Ctrl+C)');
          unawaited(_handleShutdown(defaultGracefulShutdownTimeout));
        }),
      );

      // Dart cannot watch SIGTERM on Windows. WinSW sends Ctrl+C (SIGINT);
      // registering SIGTERM used to throw and leave initialization incomplete.
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
  /// [onComplete] runs after shutdown, including skipped or failed callbacks.
  /// A timeout stops waiting; it does not cancel the callback's underlying work.
  void registerCallback(
    ShutdownCallback callback, {
    void Function()? onComplete,
    void Function()? onStart,
  }) {
    if (onStart != null) _startCallbacks.add(onStart);
    if (onComplete != null) _completionCallbacks.add(onComplete);
    _shutdownCallbacks.add(callback);
    LoggerService.debug(
      'Shutdown callback registrado. Total: ${_shutdownCallbacks.length}',
    );
  }

  /// Executa o shutdown gracioso manualmente.
  ///
  /// Use este método para encerrar o serviço de forma controlada.
  Future<void> shutdown({
    Duration timeout = defaultGracefulShutdownTimeout,
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
    for (final start in _startCallbacks) {
      try {
        start();
      } on Object catch (e, s) {
        LoggerService.error('Erro ao preparar shutdown', e, s);
      }
    }
    final shutdownWatch = Stopwatch()..start();

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
      final elapsed = shutdownWatch.elapsed;
      final remaining = timeout - elapsed;

      if (remaining <= Duration.zero) {
        callbacksSkippedByTimeout = i + 1;
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
        await Future<void>.sync(() => callback(remaining)).timeout(remaining);
        stopwatch.stop();
        final stillRemaining = timeout - shutdownWatch.elapsed;

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

    final totalElapsed = shutdownWatch.elapsed;
    LoggerService.info('═══════════════════════════════════════');
    LoggerService.info(
      '✅ SHUTDOWN CONCLUÍDO | '
      'Tempo: ${totalElapsed.inSeconds}s | '
      'Executados: $callbacksExecuted'
      '${callbacksSkippedByTimeout > 0 ? " | Ignorados (timeout): $callbacksSkippedByTimeout" : ""}',
    );
    LoggerService.info('═══════════════════════════════════════');
    LoggerService.info('');

    // Cancel signal subscriptions so stale listeners don't fire after exit.
    for (final sub in _signalSubscriptions) {
      try {
        await sub.cancel();
      } on Object catch (_) {}
    }
    _signalSubscriptions.clear();
    for (final complete in _completionCallbacks) {
      try {
        complete();
      } on Object catch (e, s) {
        LoggerService.error('Erro ao concluir shutdown', e, s);
      }
    }
  }

  /// Verifica se o processo está em shutdown.
  bool get isShuttingDown => _isShuttingDown;

  /// Verifica se o handler está inicializado.
  bool get isInitialized => _isInitialized;

  /// Cancela todas as subscriptions de sinal e limpa callbacks.
  /// Idempotente — chamadas subsequentes são no-op.
  ///
  /// Usado por:
  /// - Testes que precisam de estado limpo entre runs.
  /// - Hot reload em desenvolvimento (callbacks antigos não devem
  ///   acumular).
  /// - Cleanup explícito em paths alternativos de bootstrap.
  Future<void> dispose() async {
    for (final sub in _signalSubscriptions) {
      try {
        await sub.cancel();
      } on Object catch (_) {}
    }
    _signalSubscriptions.clear();
    _shutdownCallbacks.clear();
    _completionCallbacks.clear();
    _startCallbacks.clear();
    _isShuttingDown = false;
    _isInitialized = false;
  }
}
