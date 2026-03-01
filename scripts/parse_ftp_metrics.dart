// ignore_for_file: avoid_print - script CLI usa print para saída ao usuário
//
// Parser de logs FTP para extrair métricas de operação.
// Uso: dart run scripts/parse_ftp_metrics.dart [opções] [arquivo.log ...]
//   - Sem arquivos: lê da entrada padrão (stdin)
//   - --export csv|json: exporta eventos para arquivo
//   - --since YYYY-MM-DD: filtra linhas a partir da data
//   - --until YYYY-MM-DD: filtra linhas até a data
//

import 'dart:convert';
import 'dart:io';

import 'package:backup_database/scripts/ftp_metrics_parser.dart';

void main(List<String> args) async {
  final filteredArgs = _filterFlagArgs(args);
  final parser = FtpMetricsParser();
  final exportFormat = _parseExport(args);
  final since = _parseDate(args, '--since');
  final until = _parseDate(args, '--until');
  final filePaths = filteredArgs;

  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  final lines = <String>[];
  if (filePaths.isEmpty) {
    lines.addAll(
      await stdin.transform(utf8.decoder).transform(const LineSplitter()).toList(),
    );
  } else {
    for (final path in filePaths) {
      final file = File(path);
      if (!file.existsSync()) {
        print('Arquivo não encontrado: $path');
        exit(1);
      }
      lines.addAll(file.readAsLinesSync());
    }
  }

  final result = parser.parse(
    lines,
    since: since,
    until: until,
  );

  _printSummary(result);

  if (exportFormat != null) {
    final outPath = 'ftp_metrics_export.${exportFormat == 'csv' ? 'csv' : 'json'}';
    if (exportFormat == 'csv') {
      File(outPath).writeAsStringSync(parser.toCsv(result));
      print('\nExportado para: $outPath');
    } else {
      File(outPath).writeAsStringSync(parser.toJson(result));
      print('\nExportado para: $outPath');
    }
  }
}

List<String> _filterFlagArgs(List<String> args) {
  final result = <String>[];
  var i = 0;
  while (i < args.length) {
    final a = args[i];
    if (a == '--export' || a == '--since' || a == '--until') {
      i += 2;
      continue;
    }
    if (a == '-h' || a == '--help') {
      i++;
      continue;
    }
    if (!a.startsWith('--')) result.add(a);
    i++;
  }
  return result;
}

String? _parseExport(List<String> args) {
  final idx = args.indexOf('--export');
  if (idx < 0 || idx >= args.length - 1) return null;
  final v = args[idx + 1].toLowerCase();
  return (v == 'csv' || v == 'json') ? v : null;
}

DateTime? _parseDate(List<String> args, String flag) {
  final idx = args.indexOf(flag);
  if (idx < 0 || idx >= args.length - 1) return null;
  return DateTime.tryParse(args[idx + 1]);
}

void _printUsage() {
  print(r'''
Uso: dart run scripts/parse_ftp_metrics.dart [opções] [arquivo.log ...]

Opções:
  --export csv|json   Exporta eventos para ftp_metrics_export.csv ou .json
  --since YYYY-MM-DD  Filtra linhas a partir da data
  --until YYYY-MM-DD  Filtra linhas até a data
  -h, --help          Mostra esta ajuda

Exemplos:
  dart run scripts/parse_ftp_metrics.dart logs/app_2026-03-01.log
  dart run scripts/parse_ftp_metrics.dart --export csv logs/*.log
  type logs\app_2026-03-01.log | dart run scripts/parse_ftp_metrics.dart
''');
}

void _printSummary(FtpMetricsResult result) {
  final total = result.successCount + result.errorCount;
  final successRate = total > 0 ? (result.successCount / total * 100).toStringAsFixed(1) : '-';
  final errorRate = total > 0 ? (result.errorCount / total * 100).toStringAsFixed(1) : '-';
  final resumeRate = result.successCount > 0
      ? (result.resumeCount / result.successCount * 100).toStringAsFixed(1)
      : '-';

  print('\n=== Métricas FTP ===\n');
  print('Sucessos:     ${result.successCount}');
  print('Erros:        ${result.errorCount}');
  print('Retomadas:    ${result.resumeCount}');
  print('Fallbacks:    ${result.fallbackCount}');
  print('Integridade:  ${result.integrityErrorCount}');
  print('');
  print('Taxa de sucesso:  $successRate%');
  print('Taxa de erro:    $errorRate%');
  print('% com retomada:  $resumeRate%');
  if (result.hashDurationsMs.isNotEmpty) {
    final avg = result.hashDurationsMs.reduce((a, b) => a + b) / result.hashDurationsMs.length;
    final max = result.hashDurationsMs.reduce((a, b) => a > b ? a : b);
    print('');
    print('Hash SHA-256 (amostra): média ${avg.toStringAsFixed(0)}ms, max ${max}ms');
  }
  print('');
}
