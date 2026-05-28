import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

class SocketLoggerService {
  SocketLoggerService({
    required String logsDirectory,
    this.maxFileSize = 10 * 1024 * 1024,
  }) : _logsDirectory = logsDirectory;

  final String _logsDirectory;
  final int maxFileSize;
  File? _currentLogFile;
  bool isEnabled = true;

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

  Future<void> logSent(Message message) async {
    if (!isEnabled) return;
    await _log('[ENVIADO]', message);
  }

  Future<void> logReceived(Message message) async {
    if (!isEnabled) return;
    await _log('[RECEBIDO]', message);
  }

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

    if (message.payload.isNotEmpty) {
      final redacted = redactPayloadForLog(
        message.header.type,
        message.payload,
      );
      if (redacted.toString().length < 500) {
        await _writeLine('  Payload: $redacted');
      }
    }
  }

  /// §audit-2026-05-28 wave 2 (P1): payload de mensagens sensíveis
  /// (auth, gerenciamento de senha de DB remoto) **NUNCA** deve ser
  /// gravado em disco, mesmo na forma de hash. O hash PBKDF2 ainda
  /// vaza informação suficiente para um ataque de dicionário offline
  /// contra um servidor cuja `serverId` o atacante já conhece. Trocamos
  /// o valor por `'***'` antes de escrever.
  ///
  /// Visível para testes garantirem cobertura por tipo de mensagem.
  @visibleForTesting
  static Map<String, dynamic> redactPayloadForLog(
    MessageType type,
    Map<String, dynamic> payload,
  ) {
    final sensitiveKeysByType = _sensitiveKeysByMessageType[type];
    if (sensitiveKeysByType == null || sensitiveKeysByType.isEmpty) {
      return payload;
    }
    final redacted = <String, dynamic>{};
    for (final entry in payload.entries) {
      redacted[entry.key] = sensitiveKeysByType.contains(entry.key)
          ? '***'
          : entry.value;
    }
    return redacted;
  }

  /// Map de tipos de mensagem → set de chaves do payload cuja
  /// gravação em disco é proibida. Adicione novas mensagens
  /// sensíveis aqui (tabela estática, §5.8 dos
  /// `architectural_patterns.mdc`).
  static const Map<MessageType, Set<String>> _sensitiveKeysByMessageType = {
    MessageType.authRequest: {'passwordHash', 'password'},
    MessageType.authResponse: {'token', 'sessionToken'},
    MessageType.authChallenge: {'nonce'},
    MessageType.createDatabaseConfigRequest: {'password', 'cryptKey'},
    MessageType.updateDatabaseConfigRequest: {'password', 'cryptKey'},
    MessageType.testDatabaseConnectionRequest: {'password'},
  };

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

  String get logsDirectory => _logsDirectory;
}
