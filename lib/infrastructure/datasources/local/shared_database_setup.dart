import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Applied in the background database isolate, before Drift opens/migrates.
/// WAL permits UI reads during service writes; busy_timeout serializes writers.
void configureSharedDatabase(
  Database database, {
  bool synchronizeWindowsPermissions = false,
}) {
  database.execute('PRAGMA busy_timeout = 5000');
  database.execute('PRAGMA journal_mode = WAL');
  if (!Platform.isWindows || !synchronizeWindowsPermissions) return;
  final path =
      database
              .select('PRAGMA database_list')
              .firstWhere((row) => row['name'] == 'main')['file']
          as String;
  if (path.isEmpty) return;
  // Materialize WAL/SHM under the executor account before copying the existing
  // database DACL. Never add Everyone/Users permissions or copy owner/SACL.
  database.execute('BEGIN IMMEDIATE');
  try {
    synchronizeDatabaseSidecarAccess(path);
  } finally {
    database.execute('ROLLBACK');
  }
}

void synchronizeDatabaseSidecarAccess(String databasePath) {
  final result = Process.runSync(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      r'''
$ErrorActionPreference = 'Stop'
$path = $env:BACKUP_DATABASE_ACL_SOURCE
$section = [System.Security.AccessControl.AccessControlSections]::Access
$source = ([System.IO.File]::GetAccessControl($path)).GetSecurityDescriptorSddlForm($section)
foreach ($suffix in @('-wal', '-shm')) {
  $target = $path + $suffix
  if ([System.IO.File]::Exists($target)) {
    $acl = [System.IO.File]::GetAccessControl($target)
    if ($acl.GetSecurityDescriptorSddlForm($section) -ne $source) {
      $acl.SetSecurityDescriptorSddlForm($source, $section)
      [System.IO.File]::SetAccessControl($target, $acl)
    }
  }
}
''',
    ],
    environment: {'BACKUP_DATABASE_ACL_SOURCE': databasePath},
  );
  if (result.exitCode != 0) {
    throw StateError(
      'Não foi possível preservar as permissões dos arquivos SQLite auxiliares: ${result.stderr}',
    );
  }
}
