import 'dart:async';
import 'dart:io' show pid;

import 'package:backup_database/core/logging/file_logger_service.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:logger/logger.dart';

/// Resultado observable da inicialização do logger — permite o bootstrap
/// detectar falhas silenciosas (`fileLogger` nulo, write probe falhou)
/// e expor um diagnóstico ao usuário em vez de virar uma instalação
/// "sem logs" (audit 2026-05-28: app rodou ~8 dias sem gerar nenhum
/// `app_*.log` e ninguém percebeu).
class LoggerHealth {
  const LoggerHealth({
    required this.fileLoggingEnabled,
    required this.lastBootSentinelWrittenAt,
    required this.logsDirectory,
    this.initError,
    this.lastBootSentinelError,
  });

  /// True se o `FileLoggerService` está pronto e respondendo a writes.
  final bool fileLoggingEnabled;

  /// Quando a linha sentinel de boot foi escrita com sucesso. `null` =
  /// nunca escreveu (degraded).
  final DateTime? lastBootSentinelWrittenAt;

  /// Diretório que o logger usa (informativo para diagnóstico na UI).
  final String? logsDirectory;

  /// Exceção do `init()`, se houver.
  final Object? initError;

  /// Exceção da escrita sentinel, se houver — distingue de [initError]
  /// porque o `initialize` pode ter passado mas o probe write falhou.
  final Object? lastBootSentinelError;

  bool get isHealthy => fileLoggingEnabled && initError == null;
}

class LoggerService {
  static Logger? _logger;
  static FileLoggerService? _fileLogger;
  static int _silenceDepth = 0;
  static LoggerHealth _health = const LoggerHealth(
    fileLoggingEnabled: false,
    lastBootSentinelWrittenAt: null,
    logsDirectory: null,
  );

  static Logger get _instance {
    _logger ??= Logger(
      printer: PrettyPrinter(
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
    return _logger!;
  }

  /// Diagnóstico do estado do file logger — útil para o bootstrap
  /// detectar "logs silenciados" (causa de incidentes da auditoria
  /// 2026-05-28).
  static LoggerHealth get health => _health;

  /// Inicializa o LoggerService com suporte a arquivos. Sempre escreve
  /// uma linha sentinel `[boot] LoggerService initialized at <iso>` —
  /// se essa linha não aparecer em nenhum `app_*.log` recente, está
  /// claro que o file logging quebrou (vs. silêncio normal).
  static Future<void> init({String? logsDirectory}) async {
    _logger ??= Logger(
      printer: PrettyPrinter(
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );

    if (logsDirectory == null) {
      _health = LoggerHealth(
        fileLoggingEnabled: false,
        lastBootSentinelWrittenAt: null,
        logsDirectory: logsDirectory,
      );
      return;
    }

    Object? initError;
    Object? sentinelError;
    DateTime? sentinelWrittenAt;

    try {
      _fileLogger = FileLoggerService(logsDirectory: logsDirectory);
      await _fileLogger!.initialize();
    } on Object catch (e, stackTrace) {
      initError = e;
      _fileLogger = null;
      _instance.w(
        'Falha ao inicializar file logger em: $logsDirectory',
        error: e,
        stackTrace: stackTrace,
      );
    }

    final fileLogger = _fileLogger;
    if (fileLogger != null) {
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        // Linha sentinel: marcador que TEM que aparecer no log do dia.
        // Se a auditoria perceber arquivos `app_*.log` SEM essa linha,
        // o init foi enganoso (file existe mas writes não chegam).
        await fileLogger.log(
          '[boot] LoggerService sentinel '
          'pid=$pid logsDirectory=$logsDirectory utc=$now',
        );
        sentinelWrittenAt = DateTime.now();
      } on Object catch (e, stackTrace) {
        sentinelError = e;
        _instance.w(
          'LoggerService sentinel write falhou em: $logsDirectory',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    _health = LoggerHealth(
      fileLoggingEnabled: _fileLogger != null && sentinelError == null,
      lastBootSentinelWrittenAt: sentinelWrittenAt,
      logsDirectory: logsDirectory,
      initError: initError,
      lastBootSentinelError: sentinelError,
    );
  }

  /// Reseta o estado mantido para testes determinísticos.
  static void resetForTesting() {
    _fileLogger = null;
    _logger = null;
    _silenceDepth = 0;
    _health = const LoggerHealth(
      fileLoggingEnabled: false,
      lastBootSentinelWrittenAt: null,
      logsDirectory: null,
    );
  }

  static FileLoggerService? get fileLogger => _fileLogger;
  static bool get isSilenced => _silenceDepth > 0;

  static String _messageWithContext(String message) => LogContext.hasContext
      ? '${LogContext.buildStructuredPrefix()}$message'
      : message;

  static void _enqueueFileLog(Future<void>? future) {
    if (future != null) {
      unawaited(future);
    }
  }

  static Future<T> runSilenced<T>(Future<T> Function() action) async {
    _silenceDepth++;
    try {
      return await action();
    } finally {
      _silenceDepth--;
    }
  }

  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(
      _LogSeverity.debug,
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(
      _LogSeverity.info,
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(
      _LogSeverity.warning,
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(
      _LogSeverity.error,
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(
      _LogSeverity.fatal,
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void infoWithContext(
    String message, {
    String? requestId,
    String? runId,
    String? clientId,
    String? scheduleId,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    _log(
      _LogSeverity.info,
      message,
      error: error,
      stackTrace: stackTrace,
      callContextPrefix: _buildCallContextPrefix(
        requestId: requestId,
        runId: runId,
        clientId: clientId,
        scheduleId: scheduleId,
      ),
    );
  }

  static void warningWithContext(
    String message, {
    String? requestId,
    String? runId,
    String? clientId,
    String? scheduleId,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    _log(
      _LogSeverity.warning,
      message,
      error: error,
      stackTrace: stackTrace,
      callContextPrefix: _buildCallContextPrefix(
        requestId: requestId,
        runId: runId,
        clientId: clientId,
        scheduleId: scheduleId,
      ),
    );
  }

  static void errorWithContext(
    String message, {
    String? requestId,
    String? runId,
    String? clientId,
    String? scheduleId,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    _log(
      _LogSeverity.error,
      message,
      error: error,
      stackTrace: stackTrace,
      callContextPrefix: _buildCallContextPrefix(
        requestId: requestId,
        runId: runId,
        clientId: clientId,
        scheduleId: scheduleId,
      ),
    );
  }

  // Dispatch único compartilhado por todas as variantes (`debug`/`info`/
  // `warning`/`error`/`fatal` e suas versões `*WithContext`). Antes,
  // cada método replicava o pattern "cheque silenced → instance → file
  // logger" — 8 cópias com pequenas variações. Centralizar aqui torna
  // adições futuras (correlation id global, telemetria, sampling)
  // mudança em um único ponto.
  static void _log(
    _LogSeverity severity,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String callContextPrefix = '',
  }) {
    if (isSilenced) return;

    final consoleMessage = callContextPrefix.isEmpty
        ? message
        : callContextPrefix + message;
    switch (severity) {
      case _LogSeverity.debug:
        _instance.d(consoleMessage, error: error, stackTrace: stackTrace);
      case _LogSeverity.info:
        _instance.i(consoleMessage, error: error, stackTrace: stackTrace);
      case _LogSeverity.warning:
        _instance.w(consoleMessage, error: error, stackTrace: stackTrace);
      case _LogSeverity.error:
        _instance.e(consoleMessage, error: error, stackTrace: stackTrace);
      case _LogSeverity.fatal:
        _instance.f(consoleMessage, error: error, stackTrace: stackTrace);
    }

    final fileLogger = _fileLogger;
    if (fileLogger == null) return;

    // File logger sempre combina o prefixo per-call com o prefixo
    // estruturado do LogContext (runId/scheduleId globais) para que
    // logs persistidos sejam correlacionáveis sem depender do timing
    // de cada chamada.
    final fileMessage = callContextPrefix.isEmpty
        ? _messageWithContext(message)
        : callContextPrefix + _messageWithContext(message);
    _enqueueFileLog(fileLogger.log(fileMessage, level: severity.fileLevel));
  }

  static String _buildCallContextPrefix({
    String? requestId,
    String? runId,
    String? clientId,
    String? scheduleId,
  }) {
    final parts = <String>[];
    if (requestId != null) parts.add('requestId=$requestId');
    if (runId != null) parts.add('runId=$runId');
    if (clientId != null) parts.add('clientId=$clientId');
    if (scheduleId != null) parts.add('scheduleId=$scheduleId');
    if (parts.isEmpty) return '';
    return '${parts.map((p) => '[$p]').join()} ';
  }
}

enum _LogSeverity {
  debug(fileLevel: LogLevel.debug),
  info(fileLevel: LogLevel.info),
  warning(fileLevel: LogLevel.warning),
  error(fileLevel: LogLevel.error),
  fatal(fileLevel: LogLevel.error);

  const _LogSeverity({required this.fileLevel});

  final LogLevel fileLevel;
}
