import 'dart:async';

import 'package:backup_database/core/logging/file_logger_service.dart';
import 'package:backup_database/core/logging/log_context.dart';
import 'package:logger/logger.dart';

class LoggerService {
  static Logger? _logger;
  static FileLoggerService? _fileLogger;
  static int _silenceDepth = 0;

  static Logger get _instance {
    _logger ??= Logger(
      printer: PrettyPrinter(
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
    return _logger!;
  }

  /// Inicializa o LoggerService com suporte a arquivos
  static Future<void> init({String? logsDirectory}) async {
    _logger ??= Logger(
      printer: PrettyPrinter(
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );

    if (logsDirectory != null) {
      try {
        _fileLogger = FileLoggerService(logsDirectory: logsDirectory);
        await _fileLogger!.initialize();
        await _fileLogger!.log(
          'LoggerService inicializado com file logging em: $logsDirectory',
        );
      } on Object catch (e, stackTrace) {
        _instance.w(
          'Falha ao inicializar file logger em: $logsDirectory',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
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
