import 'dart:developer' as developer;
import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:backup_database/core/utils/sqlite_bundle_copy_exception.dart';
import 'package:backup_database/core/utils/sqlite_database_file_validation.dart';
import 'package:path/path.dart' as p;

const _logName = 'machine_storage_migration';

const int _sqliteQuickCheckRetryCount = 3;
const Duration _sqliteQuickCheckRetryDelay = Duration(milliseconds: 200);

const List<String> legacySqliteDatabaseBaseNames = <String>[
  'backup_database',
  'backup_database_client',
];

const Set<String> _skippedWindowsUserProfileDirNames = <String>{
  'All Users',
  'Default',
  'Default User',
  'Public',
};

class LegacyUserLogsMigrationResult {
  const LegacyUserLogsMigrationResult({
    required this.skippedNonWindows,
    required this.alreadyCompletedBeforeRun,
    required this.filesCopiedThisRun,
    required this.machineImportDirectoryPath,
    required this.hadCopyFailures,
  });

  final bool skippedNonWindows;
  final bool alreadyCompletedBeforeRun;
  final int filesCopiedThisRun;
  final String? machineImportDirectoryPath;
  final bool hadCopyFailures;
}

class MachineLegacyMigrationSummary {
  const MachineLegacyMigrationSummary({
    required this.copiedAnySqliteBundle,
    required this.legacyMarkerExists,
    required this.machineRootPath,
    required this.dataDirectoryPath,
    required this.legacyUserAppDataPath,
  });

  final bool copiedAnySqliteBundle;
  final bool legacyMarkerExists;
  final String machineRootPath;
  final String dataDirectoryPath;
  final String? legacyUserAppDataPath;
}

Future<void> ensureMachineStorageDirectoriesExist() async {
  final root = await resolveMachineRootDirectory();
  if (Platform.isWindows) {
    await Directory(p.join(root.path, MachineStorageLayout.data)).create(
      recursive: true,
    );
    await Directory(p.join(root.path, MachineStorageLayout.logs)).create(
      recursive: true,
    );
    await Directory(p.join(root.path, MachineStorageLayout.locks)).create(
      recursive: true,
    );
    await Directory(
      p.join(
        root.path,
        MachineStorageLayout.staging,
        MachineStorageLayout.stagingBackups,
      ),
    ).create(recursive: true);
    await Directory(p.join(root.path, MachineStorageLayout.config)).create(
      recursive: true,
    );
    await Directory(p.join(root.path, MachineStorageLayout.secrets)).create(
      recursive: true,
    );
    return;
  }

  await Directory(p.join(root.path, MachineStorageLayout.logs)).create(
    recursive: true,
  );
  await Directory(p.join(root.path, 'backups')).create(recursive: true);
  await Directory(p.join(root.path, MachineStorageLayout.locks)).create(
    recursive: true,
  );
}

Future<MachineLegacyMigrationSummary>
ensureLegacyAppDataMigratedToMachineScope() async {
  final machineRoot = await resolveMachineRootDirectory();
  final dataDir = await resolveMachineDataDirectory();
  final legacyUserPath =
      (await resolveLegacyWindowsUserAppDataDirectory())?.path;

  if (!Platform.isWindows) {
    return MachineLegacyMigrationSummary(
      copiedAnySqliteBundle: false,
      legacyMarkerExists: false,
      machineRootPath: machineRoot.path,
      dataDirectoryPath: dataDir.path,
      legacyUserAppDataPath: legacyUserPath,
    );
  }

  await ensureMachineStorageDirectoriesExist();

  final legacyDir = await resolveLegacyWindowsUserAppDataDirectory();
  if (legacyDir == null) {
    return MachineLegacyMigrationSummary(
      copiedAnySqliteBundle: false,
      legacyMarkerExists: await _legacyMarkerExists(machineRoot),
      machineRootPath: machineRoot.path,
      dataDirectoryPath: dataDir.path,
      legacyUserAppDataPath: null,
    );
  }

  await dataDir.create(recursive: true);

  var migratedAny = false;
  for (final baseName in legacySqliteDatabaseBaseNames) {
    try {
      final copied = await migrateSqliteDatabaseBundleIfNeeded(
        legacyDir: legacyDir,
        dataDir: dataDir,
        baseName: baseName,
      );
      if (copied) {
        migratedAny = true;
      }
    } on SqliteBundleCopyException catch (e, s) {
      developer.log(
        'SQLite bundle migration failed for $baseName',
        name: _logName,
        error: e,
        stackTrace: s,
      );
    }
  }

  if (migratedAny) {
    await _writeMigrationMarker(machineRoot);
  }

  return MachineLegacyMigrationSummary(
    copiedAnySqliteBundle: migratedAny,
    legacyMarkerExists: await _legacyMarkerExists(machineRoot),
    machineRootPath: machineRoot.path,
    dataDirectoryPath: dataDir.path,
    legacyUserAppDataPath: legacyDir.path,
  );
}

Future<bool> _legacyMarkerExists(Directory machineRoot) async {
  final marker = File(
    p.join(
      machineRoot.path,
      MachineStorageLayout.config,
      MachineStorageLayout.legacyAppdataMigrationMarker,
    ),
  );
  return marker.exists();
}

Future<bool> migrateSqliteDatabaseBundleIfNeeded({
  required Directory legacyDir,
  required Directory dataDir,
  required String baseName,
  bool runQuickCheck = true,
}) async {
  final destDb = File(p.join(dataDir.path, '$baseName.db'));
  if (await destDb.exists()) {
    final len = await destDb.length();
    if (len > 0) {
      return false;
    }
  }

  final sourceDb = File(p.join(legacyDir.path, '$baseName.db'));
  if (!await sourceDb.exists()) {
    return false;
  }
  if (await sourceDb.length() == 0) {
    return false;
  }

  if (!await sqliteDatabaseFileHasValidHeader(sourceDb)) {
    developer.log(
      'Skipping SQLite bundle migration: invalid SQLite header for '
      '$baseName',
      name: _logName,
    );
    return false;
  }

  if (runQuickCheck) {
    var qc = SqliteQuickCheckResult.inaccessible;
    for (var attempt = 0; attempt < _sqliteQuickCheckRetryCount; attempt++) {
      qc = await sqliteDatabaseQuickCheckFile(sourceDb);
      if (qc != SqliteQuickCheckResult.inaccessible) {
        break;
      }
      if (attempt < _sqliteQuickCheckRetryCount - 1) {
        await Future<void>.delayed(_sqliteQuickCheckRetryDelay);
      }
    }
    if (qc == SqliteQuickCheckResult.failed) {
      developer.log(
        'Skipping SQLite bundle migration: PRAGMA quick_check failed for '
        '$baseName',
        name: _logName,
      );
      return false;
    }
    if (qc == SqliteQuickCheckResult.inaccessible) {
      developer.log(
        'Skipping SQLite bundle migration: database locked or unreadable '
        'for $baseName',
        name: _logName,
      );
      return false;
    }
  }

  final copiedDestinationFiles = <File>[];
  try {
    const suffixes = <String>['.db', '.db-wal', '.db-shm'];
    for (final suffix in suffixes) {
      final fileName = '$baseName$suffix';
      final src = File(p.join(legacyDir.path, fileName));
      if (await src.exists()) {
        final dst = File(p.join(dataDir.path, fileName));
        await dst.parent.create(recursive: true);
        await src.copy(dst.path);
        copiedDestinationFiles.add(dst);
      }
    }
  } on FileSystemException catch (e) {
    await _deleteFilesBestEffort(copiedDestinationFiles);
    throw SqliteBundleCopyException(baseName, e);
  }

  developer.log(
    'Migrated SQLite bundle $baseName from legacy user AppData to '
    'machine data directory',
    name: _logName,
  );
  return true;
}

Future<void> _deleteFilesBestEffort(List<File> files) async {
  for (final file in files) {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Ignore cleanup failures after a copy error.
    }
  }
}

Future<void> _writeMigrationMarker(Directory machineRoot) async {
  final marker = File(
    p.join(
      machineRoot.path,
      MachineStorageLayout.config,
      MachineStorageLayout.legacyAppdataMigrationMarker,
    ),
  );
  await marker.parent.create(recursive: true);
  await marker.writeAsString(
    'completed_at_utc=${DateTime.now().toUtc().toIso8601String()}\n',
    flush: true,
  );
}

String _normalizePathForComparison(String path) =>
    p.normalize(path).toLowerCase();

String legacyWindowsProfileFolderLabel(
  String legacyBackupDatabaseDirectoryPath,
) {
  final normalized = legacyBackupDatabaseDirectoryPath.replaceAll('/', r'\');
  final lower = normalized.toLowerCase();
  const needle = r'\users\';
  final idx = lower.indexOf(needle);
  if (idx < 0) {
    return legacyBackupDatabaseDirectoryPath;
  }
  final start = idx + needle.length;
  if (start >= normalized.length) {
    return legacyBackupDatabaseDirectoryPath;
  }
  final rest = normalized.substring(start);
  final sepIdx = rest.indexOf(r'\');
  if (sepIdx <= 0) {
    return rest.isEmpty ? legacyBackupDatabaseDirectoryPath : rest;
  }
  return rest.substring(0, sepIdx);
}

Future<List<String>> findLegacyBackupDatabasePathsOutsideCurrentUser({
  Directory? usersRootOverride,
  String? currentUserLegacyPathOverride,
}) async {
  final runScan = Platform.isWindows || usersRootOverride != null;
  if (!runScan) {
    return const <String>[];
  }

  final String? currentNormalized;
  if (currentUserLegacyPathOverride != null) {
    currentNormalized = _normalizePathForComparison(
      currentUserLegacyPathOverride,
    );
  } else {
    final legacy = await resolveLegacyWindowsUserAppDataDirectory();
    currentNormalized = legacy != null
        ? _normalizePathForComparison(legacy.path)
        : null;
  }

  final usersRoot = usersRootOverride ?? Directory(r'C:\Users');
  if (!await usersRoot.exists()) {
    return const <String>[];
  }

  final results = <String>[];
  await for (final FileSystemEntity entity in usersRoot.list()) {
    if (entity is! Directory) {
      continue;
    }
    final name = p.basename(entity.path);
    if (_skippedWindowsUserProfileDirNames.contains(name)) {
      continue;
    }
    final legacyPath = p.join(
      entity.path,
      'AppData',
      'Roaming',
      'Backup Database',
    );
    if (currentNormalized != null &&
        _normalizePathForComparison(legacyPath) == currentNormalized) {
      continue;
    }
    try {
      if (await _directoryHasNonEmptyLegacySqlite(legacyPath)) {
        results.add(p.normalize(legacyPath));
      }
    } on FileSystemException {
      continue;
    }
  }
  results.sort();
  return results;
}

Future<bool> _directoryHasNonEmptyLegacySqlite(String legacyPath) async {
  final dir = Directory(legacyPath);
  if (!await dir.exists()) {
    return false;
  }
  for (final baseName in legacySqliteDatabaseBaseNames) {
    final f = File(p.join(legacyPath, '$baseName.db'));
    if (await f.exists() &&
        await f.length() > 0 &&
        await sqliteDatabaseFileHasValidHeader(f)) {
      return true;
    }
  }
  return false;
}

Future<({int count, String? directoryPath})>
countLegacyLogFilesVisibleForCurrentUser() async {
  if (!Platform.isWindows) {
    return (count: 0, directoryPath: null);
  }
  final legacy = await resolveLegacyWindowsUserAppDataDirectory();
  if (legacy == null) {
    return (count: 0, directoryPath: null);
  }
  final logsDir = Directory(
    p.join(legacy.path, MachineStorageLayout.logs),
  );
  if (!await logsDir.exists()) {
    return (count: 0, directoryPath: logsDir.path);
  }
  var n = 0;
  await for (final FileSystemEntity e in logsDir.list(
    followLinks: false,
  )) {
    if (e is File) {
      n++;
    }
  }
  return (count: n, directoryPath: logsDir.path);
}

Future<LegacyUserLogsMigrationResult>
migrateLegacyUserLogFilesToMachineScopeIfNeeded({
  Directory? machineRootOverride,
  Directory? legacyAppDataOverride,
}) async {
  if (!Platform.isWindows && machineRootOverride == null) {
    return const LegacyUserLogsMigrationResult(
      skippedNonWindows: true,
      alreadyCompletedBeforeRun: false,
      filesCopiedThisRun: 0,
      machineImportDirectoryPath: null,
      hadCopyFailures: false,
    );
  }

  final machineRoot =
      machineRootOverride ?? await resolveMachineRootDirectory();
  final marker = File(
    p.join(
      machineRoot.path,
      MachineStorageLayout.config,
      MachineStorageLayout.legacyAppdataLogsMigrationMarker,
    ),
  );
  final importDir = Directory(
    p.join(
      machineRoot.path,
      MachineStorageLayout.logs,
      MachineStorageLayout.legacyImportedLogsSubdirectory,
    ),
  );

  if (await marker.exists()) {
    return LegacyUserLogsMigrationResult(
      skippedNonWindows: false,
      alreadyCompletedBeforeRun: true,
      filesCopiedThisRun: 0,
      machineImportDirectoryPath: importDir.path,
      hadCopyFailures: false,
    );
  }

  if (machineRootOverride == null) {
    await ensureMachineStorageDirectoriesExist();
  } else {
    await Directory(p.join(machineRoot.path, MachineStorageLayout.logs)).create(
      recursive: true,
    );
    await Directory(
      p.join(machineRoot.path, MachineStorageLayout.config),
    ).create(recursive: true);
  }

  final legacyApp =
      legacyAppDataOverride ?? await resolveLegacyWindowsUserAppDataDirectory();
  if (legacyApp == null) {
    await _writeLegacyLogsMigrationMarker(marker, filesCopied: 0);
    return LegacyUserLogsMigrationResult(
      skippedNonWindows: false,
      alreadyCompletedBeforeRun: false,
      filesCopiedThisRun: 0,
      machineImportDirectoryPath: importDir.path,
      hadCopyFailures: false,
    );
  }

  final legacyLogsDir = Directory(
    p.join(legacyApp.path, MachineStorageLayout.logs),
  );
  if (!await legacyLogsDir.exists()) {
    await _writeLegacyLogsMigrationMarker(marker, filesCopied: 0);
    return LegacyUserLogsMigrationResult(
      skippedNonWindows: false,
      alreadyCompletedBeforeRun: false,
      filesCopiedThisRun: 0,
      machineImportDirectoryPath: importDir.path,
      hadCopyFailures: false,
    );
  }

  await importDir.create(recursive: true);

  var copied = 0;
  var hadFailures = false;
  await for (final entity in legacyLogsDir.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final baseName = p.basename(entity.path);
    if (baseName.isEmpty || baseName == '.' || baseName == '..') {
      continue;
    }
    final dest = File(p.join(importDir.path, baseName));
    try {
      final srcLen = await entity.length();
      if (await dest.exists()) {
        final dstLen = await dest.length();
        if (dstLen == srcLen) {
          continue;
        }
      }
      await entity.copy(dest.path);
      copied++;
    } on Object catch (e, st) {
      hadFailures = true;
      developer.log(
        'Failed to copy legacy log file to machine scope: $baseName — $e',
        name: _logName,
        error: e,
        stackTrace: st,
      );
    }
  }

  if (!hadFailures) {
    await _writeLegacyLogsMigrationMarker(marker, filesCopied: copied);
  }

  if (copied > 0) {
    developer.log(
      'Migrated $copied legacy user log file(s) to ${importDir.path}',
      name: _logName,
    );
  }

  return LegacyUserLogsMigrationResult(
    skippedNonWindows: false,
    alreadyCompletedBeforeRun: false,
    filesCopiedThisRun: copied,
    machineImportDirectoryPath: importDir.path,
    hadCopyFailures: hadFailures,
  );
}

Future<void> _writeLegacyLogsMigrationMarker(
  File marker, {
  required int filesCopied,
}) async {
  await marker.parent.create(recursive: true);
  await marker.writeAsString(
    'completed_at_utc=${DateTime.now().toUtc().toIso8601String()}\n'
    'files_copied=$filesCopied\n',
    flush: true,
  );
}
