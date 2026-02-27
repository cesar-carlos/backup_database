/// Utilities for embedding and extracting backup ID in destination paths
/// for Sybase chain-aware retention.
///
/// Convention: suffix `_b` + first 8 chars of UUID (e.g. `_b550e8400`).
/// Enables cleanup to skip protected backups when deleting old files.
class SybaseBackupPathSuffix {
  SybaseBackupPathSuffix._();

  static const String _prefix = '_b';

  static const int _shortIdLength = 8;

  static final RegExp _extractInPathPattern = RegExp(
    '$_prefix([a-f0-9]{$_shortIdLength})',
    caseSensitive: false,
  );

  static String buildDestinationName(String baseName, String backupId) {
    if (backupId.length < _shortIdLength) return baseName;
    final short = backupId.substring(0, _shortIdLength).toLowerCase();
    final lastDot = baseName.lastIndexOf('.');
    if (lastDot > 0) {
      final name = baseName.substring(0, lastDot);
      final ext = baseName.substring(lastDot);
      return '$name$_prefix$short$ext';
    }
    return '$baseName$_prefix$short';
  }

  static String? extractShortIdFromPath(String path) {
    final match = _extractInPathPattern.firstMatch(path);
    return match?.group(1)?.toLowerCase();
  }

  static bool isPathProtected(String path, Set<String> protectedShortIds) {
    final extracted = extractShortIdFromPath(path);
    if (extracted == null) return false;
    return protectedShortIds.contains(extracted);
  }

  static Set<String> toShortIds(Set<String> fullIds) {
    return fullIds
        .where((id) => id.length >= _shortIdLength)
        .map((id) => id.substring(0, _shortIdLength).toLowerCase())
        .toSet();
  }
}
