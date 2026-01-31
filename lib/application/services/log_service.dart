import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
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
    if (level != null) {
      return _logRepository.getByLevel(level);
    }

    if (category != null) {
      return _logRepository.getByCategory(category);
    }

    if (startDate != null && endDate != null) {
      return _logRepository.getByDateRange(startDate, endDate);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      return _logRepository.search(searchQuery);
    }

    return _logRepository.getAll(limit: limit, offset: offset);
  }

  Future<rd.Result<String>> exportLogs({
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
      String extension;

      switch (format) {
        case ExportFormat.txt:
          content = _formatLogsAsTxt(logs);
          extension = 'txt';
        case ExportFormat.json:
          content = _formatLogsAsJson(logs);
          extension = 'json';
        case ExportFormat.csv:
          content = _formatLogsAsCsv(logs);
          extension = 'csv';
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'backup_logs_$timestamp.$extension';
      final filePath = p.join(outputPath, fileName);

      final file = File(filePath);
      await file.writeAsString(content);

      LoggerService.info('Logs exportados: $filePath');
      return rd.Success(filePath);
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
        final f = failure as Failure;
        LoggerService.warning('Erro ao limpar logs antigos: ${f.message}');
      },
    );

    return result;
  }
}
