import 'dart:io';

import 'package:path/path.dart' as p;

/// Politica de retencao por `lastModified` para artefatos em `remote/...`
/// (PR-4). Reutilizada em diagnostico e transferencia para a mesma
/// semantica de expiracao.
class RemoteStagingArtifactTtl {
  RemoteStagingArtifactTtl({
    this.retention = const Duration(hours: 24),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Padrao do plano: 24 h apos o mtime do arquivo de referencia.
  final Duration retention;
  final DateTime Function() _clock;

  /// `true` quando [mtime] + [retention] ja passou em relacao ao instante
  /// retornado por `_clock`.
  bool isMtimeExpired(DateTime mtime) {
    return _clock().isAfter(mtime.add(retention));
  }

  Future<bool> isFileExpiredByRetention(File file) async {
    return isMtimeExpired(await file.lastModified());
  }

  /// Para pastas (ex.: zip de `remote/<runId>/`), usa o arquivo mais recente.
  Future<bool> isDirectoryExpiredByNewestFile(Directory dir) async {
    final newest = await newestFileInTree(dir);
    if (newest == null) {
      return false;
    }
    return isFileExpiredByRetention(newest);
  }

  DateTime expiresAtForMtime(DateTime mtime) => mtime.add(retention);

  /// Arquivo mais recente por `lastModified` (desempate por path).
  static Future<File?> newestFileInTree(Directory root) async {
    File? newest;
    DateTime? newestM;
    await for (final entity in root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final m = await entity.lastModified();
        if (newestM == null || m.isAfter(newestM)) {
          newest = entity;
          newestM = m;
        }
      }
    }
    return newest;
  }
}

bool isPathUnderRemoteStaging(String allowedBase, String absoluteResolved) {
  final base = p.normalize(p.absolute(allowedBase));
  final resolved = p.normalize(p.absolute(absoluteResolved));
  if (!p.isWithin(base, resolved)) {
    return false;
  }
  final rel = p.normalize(p.relative(resolved, from: base));
  final parts = p.split(rel).where((s) => s.isNotEmpty).toList();
  return parts.isNotEmpty && parts.first == 'remote';
}
