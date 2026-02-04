import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:path/path.dart' as p;

/// Service para registrar comunicação socket entre cliente e servidor
class SocketLoggerService {
  SocketLoggerService({
    required String logsDirectory,
    this.maxFileSize = 10 * 1024 * 1024,
  }) : _logsDirectory = logsDirectory;

  final String _logsDirectory;
  final int maxFileSize;
  File? _currentLogFile;
  bool isEnabled = true;

  /// Inicializa o serviço de logging socket
  Future<void> initialize() async {
    try {
      final dir = Directory(_logsDirectory);

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await _rotateOldLogs();
      await _openCurrentLogFile();
    } on Object catch (e) {
      rethrow;
    }
  }

  /// Registra uma mensagem enviada
  Future<void> logSent(Message message) async {
    if (!isEnabled) return;
    await _log('[ENVIADO]', message);
  }

  /// Registra uma mensagem recebida
  Future<void> logReceived(Message message) async {
    if (!isEnabled) return;
    await _log('[RECEBIDO]', message);
  }

  /// Registra um evento de conexão
  Future<void> logConnectionEvent(String event) async {
    if (!isEnabled) return;
    await _writeLine('[${DateTime.now().toIso8601String()}] $event');
  }

  Future<void> _log(String direction, Message message) async {
    final timestamp = DateTime.now().toIso8601String();
    final msgType = message.header.type;
    final requestId = message.header.requestId;
    final logLine =
        '[$timestamp] $direction Type=$msgType RequestID=$requestId';

    await _writeLine(logLine);

    if (message.payload.isNotEmpty && message.payload.toString().length < 500) {
      await _writeLine('  Payload: ${message.payload}');
    }
  }

  Future<void> _writeLine(String line) async {
    try {
      final file = await _getCurrentLogFile();
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);

      final stat = await file.stat();
      if (stat.size > maxFileSize) {
        await _rotateLog();
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'SocketLoggerService: falha ao escrever linha no log',
        e,
        stackTrace,
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
    final logFileName = 'socket_$dateStr.log';
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
      LoggerService.warning(
        'SocketLoggerService: falha ao rotacionar log',
        e,
        stackTrace,
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

      if (files.length > 5) {
        final toDelete = files.sublist(0, files.length - 5);
        for (final file in toDelete) {
          try {
            await file.delete();
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'SocketLoggerService: falha ao remover log antigo: ${file.path}',
              e,
              stackTrace,
            );
          }
        }
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'SocketLoggerService: falha ao rotacionar logs antigos',
        e,
        stackTrace,
      );
    }
  }

  /// Limpa todos os logs de socket
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
      LoggerService.warning(
        'SocketLoggerService: falha ao limpar logs',
        e,
        stackTrace,
      );
    }
  }

  /// Retorna o caminho do diretório de logs
  String get logsDirectory => _logsDirectory;
}
