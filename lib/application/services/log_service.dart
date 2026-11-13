import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:intl/intl.dart';
import 'package:result_dart/result_dart.dart' as rd;

enum ExportFormat { txt, json, csv }

class LogService {
  LogService(this._logRepository);
  final IBackupLogRepository _logRepository;

  Future<rd.Result<BackupLog>> log({
    required LogLevel level,
    required LogCategory category,
    required String message,
    String? backupHistoryId,
    String? details,
  }) async {
    final log = BackupLog(
      backupHistoryId: backupHistoryId,
      level: level,
      category: category,
      message: message,
      details: details,
    );

    switch (level) {
      case LogLevel.debug:
        LoggerService.debug(message);
      case LogLevel.info:
        LoggerService.info(message);
      case LogLevel.warning:
        LoggerService.warning(message);
      case LogLevel.error:
        LoggerService.error(message);
    }

    return _logRepository.create(log);
  }

  Future<rd.Result<List<BackupLog>>> getLogs({
    int? limit,
    int? offset,
    LogLevel? level,
    LogCategory? category,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) async {
    final hasFilters =
        level != null ||
        category != null ||
        startDate != null ||
        endDate != null ||
        (searchQuery != null && searchQuery.trim().isNotEmpty);
    if (!hasFilters) return _logRepository.getAll(limit: limit, offset: offset);

    return _logRepository.getFiltered(
      limit: limit,
      offset: offset,
      level: level,
      category: category,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
    );
  }

  Future<rd.Result<String>> exportLogs({
    // Caminho completo devolvido pelo diálogo Salvar, incluindo o nome.
    required String outputPath,
    ExportFormat format = ExportFormat.txt,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      List<BackupLog> logs;

      if (startDate != null && endDate != null) {
        final result = await _logRepository.getByDateRange(startDate, endDate);
        if (result.isError()) {
          return rd.Failure(result.exceptionOrNull()!);
        }
        logs = result.getOrNull()!;
      } else {
        final result = await _logRepository.getAll();
        if (result.isError()) {
          return rd.Failure(result.exceptionOrNull()!);
        }
        logs = result.getOrNull()!;
      }

      String content;

      switch (format) {
        case ExportFormat.txt:
          content = _formatLogsAsTxt(logs);
        case ExportFormat.json:
          content = _formatLogsAsJson(logs);
        case ExportFormat.csv:
          content = _formatLogsAsCsv(logs);
      }

      final file = File(outputPath);
      await file.writeAsString(content);

      LoggerService.info('Logs exportados: $outputPath');
      return rd.Success(outputPath);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao exportar logs', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(message: 'Erro ao exportar logs: $e'),
      );
    }
  }

  String _formatLogsAsTxt(List<BackupLog> logs) {
    final buffer = StringBuffer();
    buffer.writeln('Logs do Sistema de Backup');
    buffer.writeln('Exportado em: ${DateTime.now()}');
    buffer.writeln('Total de registros: ${logs.length}');
    buffer.writeln('=' * 80);
    buffer.writeln();

    for (final log in logs) {
      buffer.writeln(
        '[${DateFormat('yyyy-MM-dd HH:mm:ss').format(log.createdAt)}] '
        '[${log.level.name.toUpperCase().padRight(7)}] '
        '[${log.category.name.toUpperCase().padRight(10)}] '
        '${log.message}',
      );
      if (log.details != null && log.details!.isNotEmpty) {
        buffer.writeln('   Detalhes: ${log.details}');
      }
    }

    return buffer.toString();
  }

  String _formatLogsAsJson(List<BackupLog> logs) {
    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'totalRecords': logs.length,
      'logs': logs
          .map(
            (log) => {
              'id': log.id,
              'backupHistoryId': log.backupHistoryId,
              'level': log.level.name,
              'category': log.category.name,
              'message': log.message,
              'details': log.details,
              'createdAt': log.createdAt.toIso8601String(),
            },
          )
          .toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  String _formatLogsAsCsv(List<BackupLog> logs) {
    final buffer = StringBuffer();
    buffer.writeln('ID,Data/Hora,Nível,Categoria,Mensagem,Detalhes,Backup ID');

    for (final log in logs) {
      buffer.writeln(
        '"${log.id}",'
        '"${DateFormat('yyyy-MM-dd HH:mm:ss').format(log.createdAt)}",'
        '"${log.level.name}",'
        '"${log.category.name}",'
        '"${_escapeCsv(log.message)}",'
        '"${_escapeCsv(log.details ?? '')}",'
        '"${log.backupHistoryId ?? ''}"',
      );
    }

    return buffer.toString();
  }

  String _escapeCsv(String value) {
    return value.replaceAll('"', '""');
  }

  Future<rd.Result<int>> cleanOldLogs() async {
    final cutoffDate = DateTime.now().subtract(
      const Duration(days: AppConstants.logRotationDays),
    );

    final result = await _logRepository.deleteOlderThan(cutoffDate);

    result.fold(
      (count) => LoggerService.info('$count logs antigos removidos'),
      (failure) {
        // Cast inseguro `failure as Failure` substituído por verificação
        // explícita: protege contra exceptions inesperadas que não
        // implementam `Failure`.
        final message = failure is Failure
            ? failure.message
            : failure.toString();
        LoggerService.warning('Erro ao limpar logs antigos: $message');
      },
    );

    return result;
  }
}
