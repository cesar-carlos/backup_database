import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';

/// Name-only predicate for Sybase-protected backup artifacts.
///
/// Drive, Dropbox and Nextcloud each list folder children via their own
/// API; the **name matching** (`_b` + 8-char backup id) was duplicated
/// in `_folderHasProtectedFile`. I/O stays in each service's retention
/// collaborator.
class ProtectedBackupFile {
  ProtectedBackupFile._();

  /// Whether [name] is a protected backup file for [protectedShortIds].
  ///
  /// Empty [protectedShortIds] or a null/empty [name] is never protected.
  static bool matchesName(
    String? name,
    Set<String> protectedShortIds,
  ) {
    if (protectedShortIds.isEmpty) return false;
    if (name == null || name.isEmpty) return false;
    return SybaseBackupPathSuffix.isPathProtected(name, protectedShortIds);
  }

  /// Whether any of [names] matches [protectedShortIds].
  static bool anyMatches(
    Iterable<String?> names,
    Set<String> protectedShortIds,
  ) {
    if (protectedShortIds.isEmpty) return false;
    for (final name in names) {
      if (matchesName(name, protectedShortIds)) return true;
    }
    return false;
  }
}
