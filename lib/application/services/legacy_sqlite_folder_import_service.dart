import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/machine_storage_migration.dart';
import 'package:backup_database/core/utils/sqlite_bundle_copy_exception.dart';
import 'package:backup_database/core/utils/sqlite_database_file_validation.dart';
import 'package:path/path.dart' as p;

class LegacySqliteFolderImportResult {
  const LegacySqliteFolderImportResult({
    required this.bundlesCopied,
    required this.bundlesSkippedDestinationNotEmpty,
    required this.bundlesSkippedSourceMissingOrEmpty,
    required this.bundlesSkippedInvalidSqliteHeader,
    required this.bundlesSkippedQuickCheckFailed,
    required this.bundlesCopyFailed,
  });

  final int bundlesCopied;
  final List<String> bundlesSkippedDestinationNotEmpty;
  final List<String> bundlesSkippedSourceMissingOrEmpty;
  final List<String> bundlesSkippedInvalidSqliteHeader;
  final List<String> bundlesSkippedQuickCheckFailed;
  final List<String> bundlesCopyFailed;
}

String _humanReadableCopyFailure(Object cause) {
  if (cause is FileSystemException) {
    final code = cause.osError?.errorCode;
    if (code == 32 || code == 33) {
      return 'file in use or locked';
    }
    return cause.message;
  }
  return cause.toString();
}

class LegacySqliteFolderImportService {
  Future<LegacySqliteFolderImportResult> importFromFolder(
    Directory sourceDir, {
    Directory? machineDataDirectoryOverride,
    bool runQuickCheck = true,
  }) async {
    final dataDir =
        machineDataDirectoryOverride ?? await resolveMachineDataDirectory();
    await dataDir.create(recursive: true);

    var copied = 0;
    final skippedDest = <String>[];
    final skippedSrc = <String>[];
    final invalidHeader = <String>[];
    final quickCheckFailed = <String>[];
    final copyFailed = <String>[];

    for (final baseName in legacySqliteDatabaseBaseNames) {
      final sourceDb = File(p.join(sourceDir.path, '$baseName.db'));
      if (!await sourceDb.exists() || await sourceDb.length() == 0) {
        skippedSrc.add(baseName);
        continue;
      }

      if (!await sqliteDatabaseFileHasValidHeader(sourceDb)) {
        invalidHeader.add(baseName);
        continue;
      }

      if (runQuickCheck) {
        final qc = await sqliteDatabaseQuickCheckFile(sourceDb);
        if (qc == SqliteQuickCheckResult.failed) {
          quickCheckFailed.add(baseName);
          continue;
        }
        if (qc == SqliteQuickCheckResult.inaccessible) {
          copyFailed.add(
            '$baseName: database locked or unreadable',
          );
          continue;
        }
      }

      final destDb = File(p.join(dataDir.path, '$baseName.db'));
      if (await destDb.exists() && await destDb.length() > 0) {
        skippedDest.add(baseName);
        continue;
      }

      try {
        final didCopy = await migrateSqliteDatabaseBundleIfNeeded(
          legacyDir: sourceDir,
          dataDir: dataDir,
          baseName: baseName,
          runQuickCheck: false,
        );
        if (didCopy) {
          copied++;
        }
      } on SqliteBundleCopyException catch (e) {
        copyFailed.add('$baseName: ${_humanReadableCopyFailure(e.cause)}');
      }
    }

    final result = LegacySqliteFolderImportResult(
      bundlesCopied: copied,
      bundlesSkippedDestinationNotEmpty: skippedDest,
      bundlesSkippedSourceMissingOrEmpty: skippedSrc,
      bundlesSkippedInvalidSqliteHeader: invalidHeader,
      bundlesSkippedQuickCheckFailed: quickCheckFailed,
      bundlesCopyFailed: copyFailed,
    );

    if (copied > 0) {
      LoggerService.info(
        'Legacy SQLite import from "${sourceDir.path}": '
        '$copied bundle(s) copied to "${dataDir.path}"',
      );
    }

    return result;
  }
}
