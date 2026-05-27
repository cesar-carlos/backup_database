import 'dart:io';

import 'package:backup_database/core/utils/appending_file_sink.dart';

class ServiceBootstrapLog {
  ServiceBootstrapLog({String? logPath}) : _logPath = logPath {
    // S3 da auditoria: rotação obrigatória — em loop de restart NSSM
    // (60s entre tentativas, ~1440 reinícios/dia), cada bootstrap
    // emite 11+ linhas. Sem rotação, o arquivo crescia GBs em horas.
    // 5 MB × 5 arquivos = ~25 MB total cap (default do AppendingFileSink).
    _sink = AppendingFileSink(
      path: path,
      maxFileSize: 5 * 1024 * 1024,
    );
  }

  static const String _defaultProgramData = r'C:\ProgramData';
  static const List<String> _relativeSegments = <String>[
    'BackupDatabase',
    'logs',
    'service_bootstrap.log',
  ];

  final String? _logPath;
  late final AppendingFileSink _sink;

  String get path => _logPath ?? _defaultLogPath();

  Future<void> append(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer('[$now] $message');
    if (error != null) {
      buffer.write('\nerror: $error');
    }
    if (stackTrace != null) {
      buffer.write('\nstack: $stackTrace');
    }
    _sink.append(buffer.toString());
  }

  /// Aguarda a fila do sink drenar. Útil em testes ou em paths de erro
  /// fatal antes de `exit()`.
  Future<void> flush() => _sink.flush();

  static String _defaultLogPath() {
    final programData =
        Platform.environment['ProgramData'] ?? _defaultProgramData;
    final separator = Platform.pathSeparator;
    final relativePath = _relativeSegments.join(separator);
    return '$programData$separator$relativePath';
  }
}
