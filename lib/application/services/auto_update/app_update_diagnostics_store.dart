import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/services/auto_update/app_update_types.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/service_mode_detector.dart';
import 'package:path/path.dart' as p;

class AppUpdateDiagnosticsStore {
  AppUpdateDiagnosticsStore({
    required this.updatesDirectoryResolver,
  });

  static const Duration diagnosticsRetention = Duration(days: 14);
  static const int maxDiagnosticsFileBytes = 256 * 1024;

  final DirectoryResolver updatesDirectoryResolver;

  Future<void> persist({
    required AppUpdateSource source,
    required int attemptNumber,
    required String currentVersion,
    required AppUpdateStage stage,
    required AppUpdateStatus status,
    required DateTime startedAt,
    required Duration duration,
    String? targetVersion,
    String? errorMessage,
    int? installerBytes,
    Duration? downloadDuration,
  }) async {
    try {
      final updatesDir = await updatesDirectoryResolver();
      await updatesDir.create(recursive: true);
      final file = File(
        p.join(updatesDir.path, AppUpdateConstants.updateDiagnosticsFileName),
      );
      await rotateIfNeeded(file);

      double? downloadMbps;
      if (installerBytes != null &&
          installerBytes > 0 &&
          downloadDuration != null &&
          downloadDuration.inMilliseconds > 0) {
        final seconds = downloadDuration.inMilliseconds / 1000.0;
        downloadMbps = (installerBytes / (1024 * 1024)) / seconds;
      }

      final record = <String, Object?>{
        'schemaVersion': AppUpdateConstants.diagnosticsSchemaVersion,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'attemptNumber': attemptNumber,
        'source': source.name,
        // §audit-2026-05-28: maquinas com UI + service ativos
        // simultaneamente nao distinguiam qual processo gerou cada
        // entry. `origin` (resolvido via installContextProvider) +
        // `processPid` permitem correlacionar com logs do processo.
        'origin': _resolveOriginLabel(),
        'processPid': pid,
        'status': status.name,
        'stage': stage.token,
        'currentVersion': currentVersion,
        'targetVersion': targetVersion,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'installerBytes': ?installerBytes,
        'downloadDurationMs': ?downloadDuration?.inMilliseconds,
        'downloadMbps': downloadMbps != null
            ? double.parse(downloadMbps.toStringAsFixed(3))
            : null,
        'error': errorMessage,
      };
      await file.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao persistir diagnostico de auto update',
        e,
        s,
      );
    }
  }

  Future<void> rotateIfNeeded(File file) async {
    if (!await file.exists()) {
      return;
    }

    final stat = await file.stat();
    final now = DateTime.now().toUtc();
    if (stat.size <= maxDiagnosticsFileBytes &&
        now.difference(stat.modified.toUtc()) <= diagnosticsRetention) {
      return;
    }

    try {
      final rotated = await compactLines(
        await file.readAsLines(),
        now: now,
      );
      if (rotated.isEmpty) {
        await file.delete();
        return;
      }
      await file.writeAsString('${rotated.join('\n')}\n', flush: true);
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao rotacionar historico de auto update',
        e,
        s,
      );
    }
  }

  static Future<List<String>> compactLines(
    List<String> lines, {
    required DateTime now,
    Duration retention = AppUpdateDiagnosticsStore.diagnosticsRetention,
    int maxBytes = AppUpdateDiagnosticsStore.maxDiagnosticsFileBytes,
  }) async {
    final cutoff = now.toUtc().subtract(retention);
    final kept = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        // Linhas legadas (sem schemaVersion) sao aceitas como
        // schemaVersion=null/0; linhas com schemaVersion futura
        // (desconhecida) sao descartadas para evitar misinterpretacao.
        final rawSchema = decoded['schemaVersion'];
        if (rawSchema != null) {
          final schema = rawSchema is int
              ? rawSchema
              : int.tryParse(rawSchema.toString());
          if (schema == null ||
              schema > AppUpdateConstants.diagnosticsSchemaVersion) {
            continue;
          }
        }

        final timestamp = _tryParseIsoDateTime(decoded['timestamp']);
        if (timestamp == null || timestamp.isBefore(cutoff)) {
          continue;
        }
        kept.add(trimmed);
      } on Object {
        continue;
      }
    }

    var estimatedBytes = kept.fold<int>(
      0,
      (total, line) => total + utf8.encode(line).length + 1,
    );
    while (kept.isNotEmpty && estimatedBytes > maxBytes) {
      final removed = kept.removeAt(0);
      estimatedBytes -= utf8.encode(removed).length + 1;
    }
    return kept;
  }

  static String _resolveOriginLabel() {
    return ServiceModeDetector.isServiceMode() ? 'service' : 'ui';
  }
}

DateTime? _tryParseIsoDateTime(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}
