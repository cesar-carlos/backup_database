import 'dart:convert';

import 'package:path/path.dart' as p;

/// Conteúdo v1 do arquivo `.lock` (lease com identidade).
class FileTransferLeaseV1 {
  FileTransferLeaseV1({
    required this.filePath,
    required this.owner,
    required this.acquiredAt,
    required this.expiresAt,
    this.runId,
  });

  final String filePath;
  final String owner;
  final String? runId;
  final DateTime acquiredAt;
  final DateTime expiresAt;

  static const int wireVersion = 1;

  Map<String, dynamic> toJson() => {
    'v': wireVersion,
    'filePath': filePath,
    'owner': owner,
    if (runId != null) 'runId': runId,
    'acquiredAt': acquiredAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  static FileTransferLeaseV1? tryParse(String text) {
    final t = text.trim();
    if (!t.startsWith('{')) {
      return null;
    }
    try {
      final raw = jsonDecode(t);
      if (raw is! Map) {
        return null;
      }
      final m = Map<String, dynamic>.from(raw);
      if (m['v'] != wireVersion) {
        return null;
      }
      final fp = m['filePath'] as String? ?? '';
      final o = m['owner'] as String? ?? 'unknown';
      final rid = m['runId'] as String?;
      final a = m['acquiredAt'] as String?;
      final e = m['expiresAt'] as String?;
      if (a == null || e == null) {
        return null;
      }
      final ac = DateTime.tryParse(a);
      final ex = DateTime.tryParse(e);
      if (ac == null || ex == null) {
        return null;
      }
      return FileTransferLeaseV1(
        filePath: fp,
        owner: o,
        acquiredAt: ac,
        expiresAt: ex,
        runId: rid,
      );
    } on Object {
      return null;
    }
  }

  /// v0: conteúdo legado = uma única data ISO 8601 (sem JSON).
  static DateTime? tryParseLegacyContent(String text) {
    final t = text.trim();
    if (t.startsWith('{')) {
      return null;
    }
    return DateTime.tryParse(t);
  }
}

/// Verdade se o mesmo ator pode re-adquirir o lease (resume na mesma sessão
/// ou outro [owner] com o mesmo [runId] após reconexão).
bool fileTransferSameLeaseHolder({
  required FileTransferLeaseV1 existing,
  required String owner,
  required String? runId,
}) {
  if (existing.owner == owner) {
    return true;
  }
  final a = runId;
  final b = existing.runId;
  if (a != null && a.isNotEmpty && a == b) {
    return true;
  }
  return false;
}

String normalizedFilePathKey(String filePath) => p.normalize(filePath);
