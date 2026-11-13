import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/execution_ownership.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/shared_database_setup.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('admin-db-');
    file = File('${directory.path}/test.db');
  });
  tearDown(() async {
    ExecutionOwnership.administrativeUi = false;
    await directory.delete(recursive: true);
  });

  test('Windows WAL files preserve the database access rules', () async {
    final database = sqlite.sqlite3.open(file.path);
    try {
      configureSharedDatabase(database);
      database.execute('CREATE TABLE acl_probe (value INTEGER)');
      final restrict = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'''
$ErrorActionPreference = 'Stop'
$path = $env:BACKUP_DATABASE_ACL_SOURCE
$acl = [System.IO.File]::GetAccessControl($path)
$acl.SetAccessRuleProtection($true, $false)
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$rule = [System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow')
$acl.AddAccessRule($rule)
[System.IO.File]::SetAccessControl($path, $acl)
''',
        ],
        environment: {'BACKUP_DATABASE_ACL_SOURCE': file.path},
      );
      expect(restrict.exitCode, 0, reason: restrict.stderr.toString());
      synchronizeDatabaseSidecarAccess(file.path);
      final check = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'''
$ErrorActionPreference = 'Stop'
$path = $env:BACKUP_DATABASE_ACL_SOURCE
$section = [System.Security.AccessControl.AccessControlSections]::Access
$source = ([System.IO.File]::GetAccessControl($path)).GetSecurityDescriptorSddlForm($section)
foreach ($suffix in @('-wal', '-shm')) {
  $actual = ([System.IO.File]::GetAccessControl($path + $suffix)).GetSecurityDescriptorSddlForm($section)
  if ($actual -ne $source) { throw 'Access rules differ' }
}
''',
        ],
        environment: {'BACKUP_DATABASE_ACL_SOURCE': file.path},
      );
      expect(check.exitCode, 0, reason: check.stderr.toString());
    } finally {
      database.close();
    }
  }, skip: !Platform.isWindows);

  test(
    'UI reads during service write and waits for concurrent writer',
    () async {
      final service = AppDatabase.forTesting(
        NativeDatabase.createInBackground(
          file,
          setup: configureSharedDatabase,
        ),
      );
      await service.customSelect('SELECT 1').get();
      await service.customStatement(
        'CREATE TABLE concurrency_probe (value INTEGER)',
      );
      ExecutionOwnership.administrativeUi = true;
      final admin = AppDatabase.forTesting(
        NativeDatabase.createInBackground(
          file,
          setup: configureSharedDatabase,
        ),
      );
      await admin.customSelect('SELECT 1').get();
      expect(
        (await admin.customSelect('PRAGMA journal_mode').getSingle())
            .data
            .values
            .single,
        'wal',
      );
      expect(
        (await admin.customSelect('PRAGMA busy_timeout').getSingle())
            .data
            .values
            .single,
        5000,
      );
      // Use an independent OS process, as in production. A native SQLite
      // busy handler in a second Dart isolate can block VM safepoints while
      // coverage runs, preventing the first isolate from committing.
      final writer = await Process.start(
        Platform.isWindows ? 'py' : 'python3',
        [
          if (Platform.isWindows) '-3',
          '-c',
          '''import sqlite3, sys, time
db = sqlite3.connect(sys.argv[1])
db.execute('BEGIN IMMEDIATE')
db.execute('INSERT INTO concurrency_probe VALUES (1)')
print('locked', flush=True)
sys.stdin.readline()
time.sleep(0.5)
db.commit()
db.close()
''',
          file.path,
        ],
      );
      final errors = writer.stderr.transform(utf8.decoder).join();
      addTearDown(() {
        writer.kill();
      });
      expect(
        await writer.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'locked',
      );
      expect(
        await admin.customSelect('SELECT * FROM concurrency_probe').get(),
        isEmpty,
      );
      writer.stdin.writeln('release');
      await writer.stdin.flush();
      await admin.customStatement(
        'INSERT INTO concurrency_probe VALUES (2)',
      );
      expect(await writer.exitCode, 0, reason: await errors);
      expect(
        (await admin.customSelect('SELECT * FROM concurrency_probe').get())
            .length,
        2,
      );
      await admin.close();
      await service.close();
    },
  );

  test('admin reads shared database without running schema repairs', () async {
    final owner = AppDatabase.forTesting(NativeDatabase(file));
    await owner.customSelect('SELECT 1').get();
    await owner.close();
    final native = sqlite.sqlite3.open(file.path);
    final before = native.select('PRAGMA schema_version').single.values.single;
    native.close();
    ExecutionOwnership.administrativeUi = true;
    final admin = AppDatabase.forTesting(NativeDatabase(file));
    await admin.customSelect('SELECT * FROM backup_logs_table').get();
    final after =
        (await admin.customSelect('PRAGMA schema_version').getSingle())
            .data
            .values
            .single;
    expect(after, before);
    await admin.close();
  });

  test(
    'admin refuses migration of older database without modifying schema',
    () async {
      final native = sqlite.sqlite3.open(file.path);
      native.execute('PRAGMA user_version = 35');
      native.execute('CREATE TABLE sentinel (value TEXT)');
      native.close();
      ExecutionOwnership.administrativeUi = true;
      final admin = AppDatabase.forTesting(NativeDatabase(file));
      await expectLater(admin.customSelect('SELECT 1').get(), throwsStateError);
      await admin.close();
      final reopened = sqlite.sqlite3.open(file.path);
      expect(reopened.select('PRAGMA user_version').single.values.single, 35);
      expect(
        reopened
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => r['name']),
        ['sentinel'],
      );
      reopened.close();
    },
  );
}
