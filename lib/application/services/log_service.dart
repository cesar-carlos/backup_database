import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../core/errors/failure.dart';
import '../../core/utils/logger_service.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/backup_log.dart';
import '../../domain/repositories/i_backup_log_repository.dart';

enum ExportFormat { txt, json, csv }

class LogService {
  final IBackupLogRepository _logRepository;

  LogService(this._logRepository);

  Future<rd.Result<BackupLog>> log({
    String? backupHistoryId,
    required LogLevel level,
    required LogCategory category,
    required String message,
    String? details,
  }) async {
    final log = BackupLog(
      backupHistoryId: backupHistoryId,
      level: level,
      category: category,
      message: message,
      details: details,
    );

    // Também logar no console
    switch (level) {
      case LogLevel.debug:
        LoggerService.debug(message);
        break;
      case LogLevel.info:
        LoggerService.info(message);
        break;
      case LogLevel.warning:
        LoggerService.warning(message);
        break;
      case LogLevel.error:
        LoggerService.error(message);
        break;
    }

    return await _logRepository.create(log);
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
      return await _logRepository.getByLevel(level);
    }

    if (category != null) {
      return await _logRepository.getByCategory(category);
    }

    if (startDate != null && endDate != null) {
      return await _logRepository.getByDateRange(startDate, endDate);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      return await _logRepository.search(searchQuery);
    }

    return await _logRepository.getAll(limit: limit, offset: offset);
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
          return rd.Failure(result.exceptionOrNull() as Exception);
        }
        logs = result.getOrNull()!;
      } else {
        final result = await _logRepository.getAll();
        if (result.isError()) {
          return rd.Failure(result.exceptionOrNull() as Exception);
        }
        logs = result.getOrNull()!;
      }

      String content;
      String extension;

      switch (format) {
        case ExportFormat.txt:
          content = _formatLogsAsTxt(logs);
          extension = 'txt';
          break;
        case ExportFormat.json:
          content = _formatLogsAsJson(logs);
          extension = 'json';
          break;
        case ExportFormat.csv:
          content = _formatLogsAsCsv(logs);
          extension = 'csv';
          break;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'backup_logs_$timestamp.$extension';
      final filePath = p.join(outputPath, fileName);

      final file = File(filePath);
      await file.writeAsString(content, encoding: utf8);

      LoggerService.info('Logs exportados: $filePath');
      return rd.Success(filePath);
    } catch (e, stackTrace) {
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
          .map((log) => {
                'id': log.id,
                'backupHistoryId': log.backupHistoryId,
                'level': log.level.name,
                'category': log.category.name,
                'message': log.message,
                'details': log.details,
                'createdAt': log.createdAt.toIso8601String(),
              })
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
      Duration(days: AppConstants.logRotationDays),
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

