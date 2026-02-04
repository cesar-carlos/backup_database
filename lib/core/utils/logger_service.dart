import 'package:backup_database/core/logging/file_logger_service.dart';
import 'package:logger/logger.dart';

class LoggerService {
  static Logger? _logger;
  static FileLoggerService? _fileLogger;

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

    // Inicializa file logger se diretório fornecido
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

  /// Retorna o FileLoggerService se disponível
  static FileLoggerService? get fileLogger => _fileLogger;

  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.d(message, error: error, stackTrace: stackTrace);
    _fileLogger?.log(message, level: LogLevel.debug);
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.i(message, error: error, stackTrace: stackTrace);
    _fileLogger?.log(message);
  }

  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.w(message, error: error, stackTrace: stackTrace);
    _fileLogger?.log(message, level: LogLevel.warning);
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.e(message, error: error, stackTrace: stackTrace);
    _fileLogger?.log(message, level: LogLevel.error);
  }

  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.f(message, error: error, stackTrace: stackTrace);
    _fileLogger?.log(message, level: LogLevel.error);
  }

  static String _contextPrefix({
    String? requestId,
    String? clientId,
    String? scheduleId,
  }) {
    final parts = <String>[];
    if (requestId != null) parts.add('requestId=$requestId');
    if (clientId != null) parts.add('clientId=$clientId');
    if (scheduleId != null) parts.add('scheduleId=$scheduleId');
    if (parts.isEmpty) return '';
    return '${parts.map((p) => '[$p]').join()} ';
  }

  static void infoWithContext(
    String message, {
    String? requestId,
    String? clientId,
    String? scheduleId,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    _instance.i(
      _contextPrefix(
            requestId: requestId?.toString(),
            clientId: clientId,
            scheduleId: scheduleId,
          ) +
          message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void warningWithContext(
    String message, {
    String? requestId,
    String? clientId,
    String? scheduleId,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    _instance.w(
      _contextPrefix(
            requestId: requestId?.toString(),
            clientId: clientId,
            scheduleId: scheduleId,
          ) +
          message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void errorWithContext(
    String message, {
    String? requestId,
    String? clientId,
    String? scheduleId,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    _instance.e(
      _contextPrefix(
            requestId: requestId?.toString(),
            clientId: clientId,
            scheduleId: scheduleId,
          ) +
          message,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
