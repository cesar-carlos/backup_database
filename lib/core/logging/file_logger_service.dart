import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

/// Service para salvar logs em arquivos rotacionados
class FileLoggerService {
  FileLoggerService({
    required String logsDirectory,
    this.maxFileSize = 10 * 1024 * 1024,
    this.maxFiles = 10,
  }) : _logsDirectory = logsDirectory;

  final String _logsDirectory;
  final int maxFileSize;
  final int maxFiles;
  File? _currentLogFile;

  /// Inicializa o serviço de logging
  Future<void> initialize() async {
    try {
      final dir = Directory(_logsDirectory);

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final testFile = File(p.join(_logsDirectory, '_test_write.tmp'));
      await testFile.writeAsString('TEST');
      await testFile.delete();

      await _rotateOldLogs();
      await _openCurrentLogFile();

      await log('FileLoggerService inicializado com sucesso!');
    } on Object catch (e) {
      rethrow;
    }
  }

  /// Registra uma mensagem de log
  Future<void> log(String message, {LogLevel level = LogLevel.info}) async {
    final timestamp = DateTime.now().toIso8601String();
    final levelStr = level.name.toUpperCase();
    final logLine = '[$timestamp] [$levelStr] $message';

    await _writeToLogFile(logLine);
  }

  Future<void> _writeToLogFile(String logLine) async {
    try {
      final file = await _getCurrentLogFile();
      await file.writeAsString(
        '$logLine\n',
        mode: FileMode.append,
        flush: true,
      );

      final stat = await file.stat();
      if (stat.size > maxFileSize) {
        await _rotateLog();
      }
    } on Object catch (e, stackTrace) {
      developer.log(
        'FileLoggerService: falha ao escrever no log',
        name: 'FileLoggerService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<File> _getCurrentLogFile() async {
    if (_currentLogFile != null && await _currentLogFile!.exists()) {
      return _currentLogFile!;
    }
    return _openCurrentLogFile();
  }

  Future<File> _openCurrentLogFile() async {
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final logFileName = 'app_$dateStr.log';
    final logFilePath = p.join(_logsDirectory, logFileName);
    _currentLogFile = File(logFilePath);
    return _currentLogFile!;
  }

  Future<void> _rotateLog() async {
    try {
      _currentLogFile = null;
      await _rotateOldLogs();
      await _openCurrentLogFile();
    } on Object catch (e, stackTrace) {
      developer.log(
        'FileLoggerService: falha ao rotacionar log',
        name: 'FileLoggerService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _rotateOldLogs() async {
    try {
      final dir = Directory(_logsDirectory);
      if (!await dir.exists()) return;

      final files = await dir
          .list()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      files.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );

      if (files.length > maxFiles) {
        final toDelete = files.sublist(0, files.length - maxFiles);
        for (final file in toDelete) {
          try {
            await file.delete();
          } on Object catch (e, stackTrace) {
            developer.log(
              'FileLoggerService: falha ao remover arquivo antigo: ${file.path}',
              name: 'FileLoggerService',
              error: e,
              stackTrace: stackTrace,
            );
          }
        }
      }
    } on Object catch (e, stackTrace) {
      developer.log(
        'FileLoggerService: falha ao rotacionar logs antigos',
        name: 'FileLoggerService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Limpa todos os logs
  Future<void> clearLogs() async {
    try {
      final dir = Directory(_logsDirectory);
      if (!await dir.exists()) return;

      await for (final file in dir.list()) {
        if (file is File) {
          await file.delete();
        }
      }
      _currentLogFile = null;
    } on Object catch (e, stackTrace) {
      developer.log(
        'FileLoggerService: falha ao limpar logs',
        name: 'FileLoggerService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Retorna o caminho do diretório de logs
  String get logsDirectory => _logsDirectory;
}

enum LogLevel {
  debug,
  info,
  warning,
  error,
}
