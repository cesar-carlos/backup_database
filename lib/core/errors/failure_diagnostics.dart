import 'dart:collection';

import 'package:backup_database/core/errors/failure.dart';

/// Preserva a cadeia de causas sem incluir credenciais comuns de transporte.
String failureDiagnostics(Object error) {
  final seen = HashSet<Object>.identity();
  final lines = <String>[];
  Object? current = error;
  while (current != null && seen.add(current) && lines.length < 8) {
    if (current is Failure) {
      lines.add(
        '${current.runtimeType}'
        '${current.code == null ? "" : " [${current.code}]"}: '
        '${current.message}',
      );
      current = current.originalError;
    } else {
      lines.add('${current.runtimeType}: $current');
      break;
    }
  }
  return redactFailureDetails(lines.join('\nCausa: '));
}

String redactFailureDetails(String text) => text
    .replaceAll(
      RegExp(
        r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----[\s\S]*?(?:-----END (?:[A-Z]+ )?PRIVATE KEY-----|$)',
      ),
      '[chave privada oculta]',
    )
    .replaceAll(
      RegExp(r'\b(Bearer|Basic)\s+[^\s,;"\x27}]+', caseSensitive: false),
      '[credencial oculta]',
    )
    .replaceAllMapped(
      RegExp(r'(https?|ftp|sftp)://[^\s/@]+:[^\s/@]+@', caseSensitive: false),
      (match) => '${match[1]}://[oculto]@',
    )
    .replaceAllMapped(
      RegExp(
        r'''(["']?(?:[\w-]*(?:password|passwd|senha|token|secret|private[_-]?key|api[_-]?key|crypt[_-]?key)[\w-]*|pwd|authorization)["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;&}]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}[oculto]',
    );
