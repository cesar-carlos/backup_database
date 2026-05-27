import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

class ServiceBootstrapLog {
  ServiceBootstrapLog({String? logPath}) : _logPath = logPath;

  static const String _defaultProgramData = r'C:\ProgramData';
  static const List<String> _relativeSegments = <String>[
    'BackupDatabase',
    'logs',
    'service_bootstrap.log',
  ];

  final String? _logPath;

  String get path => _logPath ?? _defaultLogPath();

  Future<void> append(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final now = DateTime.now().toIso8601String();
      final buffer = StringBuffer('[$now] $message');
      if (error != null) {
        buffer.write('\nerror: $error');
      }
      if (stackTrace != null) {
        buffer.write('\nstack: $stackTrace');
      }
      buffer.write('\n');
      await file.writeAsString(buffer.toString(), mode: FileMode.append);
    } on Object catch (e) {
      developer.log(
        '[ServiceBootstrapLog] write failed: $e',
        name: 'service_bootstrap',
        level: 1000,
      );
    }
  }

  static String _defaultLogPath() {
    final programData =
        Platform.environment['ProgramData'] ?? _defaultProgramData;
    final separator = Platform.pathSeparator;
    final relativePath = _relativeSegments.join(separator);
    return '$programData$separator$relativePath';
  }
}
