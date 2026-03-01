import 'dart:convert';

class FtpMetricsResult {
  FtpMetricsResult({
    required this.successCount,
    required this.errorCount,
    required this.resumeCount,
    required this.fallbackCount,
    required this.integrityErrorCount,
    required this.events,
    required this.hashDurationsMs,
  });

  final int successCount;
  final int errorCount;
  final int resumeCount;
  final int fallbackCount;
  final int integrityErrorCount;
  final List<FtpMetricEvent> events;
  final List<int> hashDurationsMs;
}

class FtpMetricEvent {
  FtpMetricEvent({
    required this.timestamp,
    required this.type,
    this.remotePath,
    this.hashDurationMs,
    this.resumeOffset,
    this.errorMessage,
  });

  final DateTime? timestamp;
  final String type;
  final String? remotePath;
  final int? hashDurationMs;
  final int? resumeOffset;
  final String? errorMessage;
}

class FtpMetricsParser {
  static final _successRegex = RegExp(
    r'Upload FTP concluído:\s*(.+?)(?:\s+\(SHA-256:\s*[^,\s]+,\s*hash\s+(\d+)ms\))?\s*$',
    caseSensitive: false,
  );

  static final _resumeRegex = RegExp(
    r'Retomando upload de .+?\s+a partir do byte\s+(\d+)',
    caseSensitive: false,
  );

  static final _fallbackRegex = RegExp(
    'fallback para upload completo|REST STREAM não suportado',
    caseSensitive: false,
  );

  static final _errorRegex = RegExp(
    'Upload FTP falhou|Erro no upload FTP',
    caseSensitive: false,
  );

  static final _integrityRegex = RegExp(
    'Erro de integridade|SIZE retornou -1',
    caseSensitive: false,
  );

  static final _timestampRegex = RegExp(
    r'^\[(\d{4}-\d{2}-\d{2}T[\d:.+-]+)\]',
  );

  FtpMetricsResult parse(
    List<String> lines, {
    DateTime? since,
    DateTime? until,
  }) {
    final events = <FtpMetricEvent>[];
    var successCount = 0;
    var errorCount = 0;
    var resumeCount = 0;
    var fallbackCount = 0;
    var integrityErrorCount = 0;
    final hashDurationsMs = <int>[];

    for (final line in lines) {
      final msg = _extractMessage(line);
      if (msg.isEmpty) continue;

      final timestamp = _extractTimestamp(line);
      if (since != null && timestamp != null && timestamp.isBefore(since)) continue;
      if (until != null && timestamp != null && timestamp.isAfter(until)) continue;

      final successMatch = _successRegex.firstMatch(msg);
      if (successMatch != null) {
        successCount++;
        events.add(FtpMetricEvent(
          timestamp: timestamp,
          type: 'success',
          remotePath: successMatch.group(1)?.trim(),
          hashDurationMs: successMatch.group(2) != null
              ? int.tryParse(successMatch.group(2)!)
              : null,
        ));
        final hashMs = successMatch.group(2) != null
            ? int.tryParse(successMatch.group(2)!)
            : null;
        if (hashMs != null) hashDurationsMs.add(hashMs);
        continue;
      }

      final resumeMatch = _resumeRegex.firstMatch(msg);
      if (resumeMatch != null) {
        resumeCount++;
        events.add(FtpMetricEvent(
          timestamp: timestamp,
          type: 'resume',
          resumeOffset: int.tryParse(resumeMatch.group(1)!),
        ));
        continue;
      }

      if (_fallbackRegex.hasMatch(msg)) {
        fallbackCount++;
        events.add(FtpMetricEvent(
          timestamp: timestamp,
          type: 'fallback',
        ));
        continue;
      }

      if (_errorRegex.hasMatch(msg)) {
        errorCount++;
        events.add(FtpMetricEvent(
          timestamp: timestamp,
          type: 'error',
          errorMessage: msg.length > 200 ? '${msg.substring(0, 200)}...' : msg,
        ));
        continue;
      }

      if (_integrityRegex.hasMatch(msg)) {
        integrityErrorCount++;
        events.add(FtpMetricEvent(
          timestamp: timestamp,
          type: 'integrity',
          errorMessage: msg.length > 200 ? '${msg.substring(0, 200)}...' : msg,
        ));
      }
    }

    return FtpMetricsResult(
      successCount: successCount,
      errorCount: errorCount,
      resumeCount: resumeCount,
      fallbackCount: fallbackCount,
      integrityErrorCount: integrityErrorCount,
      events: events,
      hashDurationsMs: hashDurationsMs,
    );
  }

  String _extractMessage(String line) {
    final tsMatch = _timestampRegex.firstMatch(line);
    if (tsMatch != null) {
      final rest = line.substring(tsMatch.end);
      final levelMatch = RegExp(r'\[\s*(\w+)\s*\]').firstMatch(rest);
      if (levelMatch != null) {
        return rest.substring(levelMatch.end).trim();
      }
      return rest.trim();
    }
    return line.trim();
  }

  DateTime? _extractTimestamp(String line) {
    final m = _timestampRegex.firstMatch(line);
    if (m == null) return null;
    return DateTime.tryParse(m.group(1)!);
  }

  String toCsv(FtpMetricsResult result) {
    final sb = StringBuffer();
    sb.writeln('timestamp,type,remote_path,hash_duration_ms,resume_offset,error_message');
    for (final e in result.events) {
      sb.writeln(
        '${e.timestamp?.toIso8601String() ?? ""},'
        '${e.type},'
        '${_escapeCsv(e.remotePath)},'
        '${e.hashDurationMs ?? ""},'
        '${e.resumeOffset ?? ""},'
        '${_escapeCsv(e.errorMessage)}',
      );
    }
    return sb.toString();
  }

  String _escapeCsv(String? s) {
    if (s == null || s.isEmpty) return '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String toJson(FtpMetricsResult result) {
    final map = {
      'summary': {
        'successCount': result.successCount,
        'errorCount': result.errorCount,
        'resumeCount': result.resumeCount,
        'fallbackCount': result.fallbackCount,
        'integrityErrorCount': result.integrityErrorCount,
        'hashDurationsMs': result.hashDurationsMs,
      },
      'events': result.events.map((e) => {
        'timestamp': e.timestamp?.toIso8601String(),
        'type': e.type,
        'remotePath': e.remotePath,
        'hashDurationMs': e.hashDurationMs,
        'resumeOffset': e.resumeOffset,
        'errorMessage': e.errorMessage,
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
