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
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      'Bearer [oculto]',
    )
    .replaceAllMapped(
      RegExp(r'(https?|ftp|sftp)://[^\s/@]+:[^\s/@]+@', caseSensitive: false),
      (match) => '${match[1]}://[oculto]@',
    )
    .replaceAllMapped(
      RegExp(
        r'''(["']?(?:password|pwd|senha|access_token|refresh_token|client_secret|authorization)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&}]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}[oculto]',
    )
    .replaceAll(
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      'Bearer [oculto]',
    );
