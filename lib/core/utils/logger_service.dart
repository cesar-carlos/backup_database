import 'package:logger/logger.dart';

class LoggerService {
  static Logger? _logger;

  static Logger get _instance {
    _logger ??= Logger(
      printer: PrettyPrinter(
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
    return _logger!;
  }

  static void init() {
    _logger ??= Logger(
      printer: PrettyPrinter(
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
  }

  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.d(message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.i(message, error: error, stackTrace: stackTrace);
  }

  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.w(message, error: error, stackTrace: stackTrace);
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.e(message, error: error, stackTrace: stackTrace);
  }

  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.f(message, error: error, stackTrace: stackTrace);
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
      ) + message,
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
      ) + message,
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
      ) + message,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
