import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:backup_database/core/utils/machine_storage_migration.dart';
import 'package:path/path.dart' as p;

const int machineStorageScopeVersion = 1;

Future<void> recordMachineStorageBootstrapDiagnostics({
  required MachineLegacyMigrationSummary migrationSummary,
  required List<String> otherLegacyProfilePaths,
  required int legacyLogFileCount,
  required String? legacyLogsDirectoryPath,
  required LegacyUserLogsMigrationResult legacyLogsMigration,
  required String secureCredentialBackendLabel,
}) async {
  final machineLogsPath = p.join(
    migrationSummary.machineRootPath,
    MachineStorageLayout.logs,
  );

  LoggerService.info(
    'Machine storage bootstrap: root=${migrationSummary.machineRootPath}; '
    'data=${migrationSummary.dataDirectoryPath}; logs=$machineLogsPath',
  );
  LoggerService.info(
    'Legacy AppData migration: marker=${migrationSummary.legacyMarkerExists}; '
    'copiedSqliteThisRun=${migrationSummary.copiedAnySqliteBundle}; '
    'currentUserLegacyPath=${migrationSummary.legacyUserAppDataPath ?? "(none)"}',
  );
  LoggerService.info(
    'Secure credential backend: $secureCredentialBackendLabel',
  );

  if (legacyLogsMigration.filesCopiedThisRun > 0) {
    LoggerService.info(
      'Legacy user log files copied to machine scope: '
      '${legacyLogsMigration.filesCopiedThisRun} -> '
      '${legacyLogsMigration.machineImportDirectoryPath ?? "(unknown)"}',
    );
  }
  if (legacyLogsMigration.hadCopyFailures) {
    LoggerService.warning(
      'Legacy user log migration had failures; will retry on next boot '
      '(marker not written). Source: '
      '${legacyLogsDirectoryPath ?? "unknown"}',
    );
  }
  if (legacyLogFileCount > 0) {
    LoggerService.info(
      'Legacy user-scope log folder still has $legacyLogFileCount file(s) at '
      '${legacyLogsDirectoryPath ?? "unknown"}; '
      'new operational logs use machine-scope under $machineLogsPath. '
      'One-time copies (if any) are under '
      '${legacyLogsMigration.machineImportDirectoryPath ?? "logs/legacy_appdata"}.',
    );
  }

  if (otherLegacyProfilePaths.isNotEmpty) {
    LoggerService.warning(
      'R1 multi-profile: other Windows profiles have legacy SQLite data under '
      r'AppData\Roaming\Backup Database. Only the current profile was used for '
      'automatic DB migration. Manual review: ${otherLegacyProfilePaths.join("; ")}',
    );
  }

  await _writeMigrationStateFile(
    migrationSummary: migrationSummary,
    otherLegacyProfilePaths: otherLegacyProfilePaths,
    legacyLogFileCount: legacyLogFileCount,
    legacyLogsDirectoryPath: legacyLogsDirectoryPath,
    legacyLogsMigration: legacyLogsMigration,
    secureCredentialBackendLabel: secureCredentialBackendLabel,
  );
}

Future<void> _writeMigrationStateFile({
  required MachineLegacyMigrationSummary migrationSummary,
  required List<String> otherLegacyProfilePaths,
  required int legacyLogFileCount,
  required String? legacyLogsDirectoryPath,
  required LegacyUserLogsMigrationResult legacyLogsMigration,
  required String secureCredentialBackendLabel,
}) async {
  final stateFile = File(
    p.join(
      migrationSummary.machineRootPath,
      MachineStorageLayout.config,
      MachineStorageLayout.migrationStateFile,
    ),
  );
  await stateFile.parent.create(recursive: true);

  final payload = <String, Object?>{
    'storageScopeVersion': machineStorageScopeVersion,
    'lastBootstrapUtc': DateTime.now().toUtc().toIso8601String(),
    'machineRoot': migrationSummary.machineRootPath,
    'dataDirectory': migrationSummary.dataDirectoryPath,
    'legacyAppDataMigration': <String, Object?>{
      'markerPresent': migrationSummary.legacyMarkerExists,
      'copiedSqliteOnLastRun': migrationSummary.copiedAnySqliteBundle,
      'currentUserLegacyPath': migrationSummary.legacyUserAppDataPath,
    },
    'secureCredentialBackend': secureCredentialBackendLabel,
    'otherProfilesWithLegacySqlitePaths': otherLegacyProfilePaths,
    'legacyUserLogs': <String, Object?>{
      'visibleFileCount': legacyLogFileCount,
      'directory': legacyLogsDirectoryPath,
    },
    'legacyUserLogsImport': <String, Object?>{
      'skippedNonWindows': legacyLogsMigration.skippedNonWindows,
      'alreadyDoneBeforeRun': legacyLogsMigration.alreadyCompletedBeforeRun,
      'filesCopiedThisRun': legacyLogsMigration.filesCopiedThisRun,
      'machineImportDirectory': legacyLogsMigration.machineImportDirectoryPath,
      'hadCopyFailures': legacyLogsMigration.hadCopyFailures,
    },
  };

  final encoded = const JsonEncoder.withIndent('  ').convert(payload);
  await stateFile.writeAsString(encoded, flush: true);
}
