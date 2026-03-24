import 'dart:io';

import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:backup_database/core/utils/machine_storage_migration.dart';
import 'package:backup_database/core/utils/sqlite_bundle_copy_exception.dart';
import 'package:backup_database/core/utils/sqlite_database_file_validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/sqlite_test_helpers.dart';

void main() {
  group('migrateSqliteDatabaseBundleIfNeeded', () {
    test('copies db bundle when destination db missing', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'machine_migration_test',
      );
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final legacyDir = Directory(p.join(tmp.path, 'legacy'))..createSync();
      final dataDir = Directory(p.join(tmp.path, 'data'))..createSync();

      final srcDbPath = p.join(legacyDir.path, 'backup_database.db');
      writeMinimalValidSqliteDbFile(srcDbPath);
      final srcDb = File(srcDbPath);

      final copied = await migrateSqliteDatabaseBundleIfNeeded(
        legacyDir: legacyDir,
        dataDir: dataDir,
        baseName: 'backup_database',
      );

      expect(copied, isTrue);
      final destDb = File(p.join(dataDir.path, 'backup_database.db'));
      expect(await destDb.length(), await srcDb.length());
    });

    test('skips copy when source has invalid SQLite header', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'machine_migration_bad_header',
      );
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final legacyDir = Directory(p.join(tmp.path, 'legacy'))..createSync();
      final dataDir = Directory(p.join(tmp.path, 'data'))..createSync();

      await File(
        p.join(legacyDir.path, 'backup_database.db'),
      ).writeAsBytes(List<int>.filled(64, 7));

      final copied = await migrateSqliteDatabaseBundleIfNeeded(
        legacyDir: legacyDir,
        dataDir: dataDir,
        baseName: 'backup_database',
      );

      expect(copied, isFalse);
      expect(
        await File(p.join(dataDir.path, 'backup_database.db')).exists(),
        isFalse,
      );
    });

    test('skips copy when quick_check fails on source', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'machine_migration_qc_fail',
      );
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final legacyDir = Directory(p.join(tmp.path, 'legacy'))..createSync();
      final dataDir = Directory(p.join(tmp.path, 'data'))..createSync();

      final srcPath = p.join(legacyDir.path, 'backup_database.db');
      writeMinimalValidSqliteDbFile(srcPath);
      final srcFile = File(srcPath);
      final bytes = await srcFile.readAsBytes();
      for (var i = kSqliteHeaderByteLength; i < bytes.length; i++) {
        bytes[i] = bytes[i] ^ 0xff;
      }
      await srcFile.writeAsBytes(bytes);

      final qc = await sqliteDatabaseQuickCheckFile(srcFile);
      expect(qc, isNot(SqliteQuickCheckResult.ok));

      final copied = await migrateSqliteDatabaseBundleIfNeeded(
        legacyDir: legacyDir,
        dataDir: dataDir,
        baseName: 'backup_database',
      );

      expect(copied, isFalse);
      expect(
        await File(p.join(dataDir.path, 'backup_database.db')).exists(),
        isFalse,
      );
    });

    test('skips when destination db already has data', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'machine_migration_skip_test',
      );
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final legacyDir = Directory(p.join(tmp.path, 'legacy'))..createSync();
      final dataDir = Directory(p.join(tmp.path, 'data'))..createSync();

      await File(
        p.join(legacyDir.path, 'backup_database.db'),
      ).writeAsBytes(List<int>.filled(10, 1));

      await File(
        p.join(dataDir.path, 'backup_database.db'),
      ).writeAsBytes(List<int>.filled(20, 2));

      final copied = await migrateSqliteDatabaseBundleIfNeeded(
        legacyDir: legacyDir,
        dataDir: dataDir,
        baseName: 'backup_database',
      );

      expect(copied, isFalse);
      expect(
        await File(p.join(dataDir.path, 'backup_database.db')).length(),
        20,
      );
    });

    test('returns false when legacy db missing', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'machine_migration_empty_test',
      );
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final legacyDir = Directory(p.join(tmp.path, 'legacy'))..createSync();
      final dataDir = Directory(p.join(tmp.path, 'data'))..createSync();

      final copied = await migrateSqliteDatabaseBundleIfNeeded(
        legacyDir: legacyDir,
        dataDir: dataDir,
        baseName: 'backup_database',
      );

      expect(copied, isFalse);
    });

    test('cleans up partial destination files when bundle copy fails', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'machine_migration_partial_cleanup',
      );
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final legacyDir = Directory(p.join(tmp.path, 'legacy'))..createSync();
      final dataDir = Directory(p.join(tmp.path, 'data'))..createSync();

      writeMinimalValidSqliteDbFile(
        p.join(legacyDir.path, 'backup_database.db'),
      );
      await File(
        p.join(legacyDir.path, 'backup_database.db-wal'),
      ).writeAsString('wal');

      Directory(
        p.join(dataDir.path, 'backup_database.db-wal'),
      ).createSync(recursive: true);

      expect(
        () => migrateSqliteDatabaseBundleIfNeeded(
          legacyDir: legacyDir,
          dataDir: dataDir,
          baseName: 'backup_database',
          runQuickCheck: false,
        ),
        throwsA(isA<SqliteBundleCopyException>()),
      );

      expect(
        await File(p.join(dataDir.path, 'backup_database.db')).exists(),
        isFalse,
      );
    });
  });

  group('findLegacyBackupDatabasePathsOutsideCurrentUser', () {
    test('lists other profiles with non-empty legacy SQLite db', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'profile_scan_test',
      );
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final aliceRoot = Directory(p.join(tmp.path, 'Alice'))..createSync();
      final bobRoot = Directory(p.join(tmp.path, 'Bob'))..createSync();
      final aliceLegacy = Directory(
        p.join(aliceRoot.path, 'AppData', 'Roaming', 'Backup Database'),
      )..createSync(recursive: true);
      final bobLegacy = Directory(
        p.join(bobRoot.path, 'AppData', 'Roaming', 'Backup Database'),
      )..createSync(recursive: true);

      writeMinimalValidSqliteDbFile(
        p.join(aliceLegacy.path, 'backup_database.db'),
      );
      writeMinimalValidSqliteDbFile(
        p.join(bobLegacy.path, 'backup_database.db'),
      );

      final found = await findLegacyBackupDatabasePathsOutsideCurrentUser(
        usersRootOverride: tmp,
        currentUserLegacyPathOverride: aliceLegacy.path,
      );

      expect(found.length, 1);
      expect(p.normalize(found.single), p.normalize(bobLegacy.path));
    });

    test('skips Public profile directory', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'profile_scan_public_test',
      );
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final aliceRoot = Directory(p.join(tmp.path, 'Alice'))..createSync();
      final publicRoot = Directory(p.join(tmp.path, 'Public'))..createSync();
      final aliceLegacy = Directory(
        p.join(aliceRoot.path, 'AppData', 'Roaming', 'Backup Database'),
      )..createSync(recursive: true);
      Directory(
        p.join(publicRoot.path, 'AppData', 'Roaming', 'Backup Database'),
      ).createSync(recursive: true);
      writeMinimalValidSqliteDbFile(
        p.join(aliceLegacy.path, 'backup_database.db'),
      );
      await File(
        p.join(
          publicRoot.path,
          'AppData',
          'Roaming',
          'Backup Database',
          'backup_database.db',
        ),
      ).writeAsBytes(List<int>.filled(8, 3));

      final found = await findLegacyBackupDatabasePathsOutsideCurrentUser(
        usersRootOverride: tmp,
        currentUserLegacyPathOverride: aliceLegacy.path,
      );

      expect(found, isEmpty);
    });
  });

  group('migrateLegacyUserLogFilesToMachineScopeIfNeeded', () {
    test('copies legacy log files once and writes marker', () async {
      final tmp = await Directory.systemTemp.createTemp('legacy_logs_mig');
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final machineRoot = Directory(p.join(tmp.path, 'machine'))..createSync();
      final legacyApp = Directory(p.join(tmp.path, 'legacy_app'))..createSync();
      final legacyLogs = Directory(p.join(legacyApp.path, 'logs'))
        ..createSync(recursive: true);
      await File(p.join(legacyLogs.path, 'a.log')).writeAsString('hello');

      final r1 = await migrateLegacyUserLogFilesToMachineScopeIfNeeded(
        machineRootOverride: machineRoot,
        legacyAppDataOverride: legacyApp,
      );

      expect(r1.filesCopiedThisRun, 1);
      expect(r1.hadCopyFailures, isFalse);
      expect(r1.alreadyCompletedBeforeRun, isFalse);
      expect(r1.skippedNonWindows, isFalse);

      final importPath = p.join(
        machineRoot.path,
        MachineStorageLayout.logs,
        MachineStorageLayout.legacyImportedLogsSubdirectory,
      );
      expect(await File(p.join(importPath, 'a.log')).readAsString(), 'hello');

      final marker = File(
        p.join(
          machineRoot.path,
          MachineStorageLayout.config,
          MachineStorageLayout.legacyAppdataLogsMigrationMarker,
        ),
      );
      expect(await marker.exists(), isTrue);

      await File(p.join(legacyLogs.path, 'b.log')).writeAsString('second');
      final r2 = await migrateLegacyUserLogFilesToMachineScopeIfNeeded(
        machineRootOverride: machineRoot,
        legacyAppDataOverride: legacyApp,
      );
      expect(r2.alreadyCompletedBeforeRun, isTrue);
      expect(r2.filesCopiedThisRun, 0);
      expect(await File(p.join(importPath, 'b.log')).exists(), isFalse);
    });

    test(
      'writes marker when destination already matches source size',
      () async {
        final tmp = await Directory.systemTemp.createTemp('legacy_logs_idem');
        addTearDown(() async {
          if (tmp.existsSync()) {
            await tmp.delete(recursive: true);
          }
        });

        final machineRoot = Directory(p.join(tmp.path, 'machine'))
          ..createSync();
        final legacyApp = Directory(p.join(tmp.path, 'legacy_app'))
          ..createSync();
        final legacyLogs = Directory(p.join(legacyApp.path, 'logs'))
          ..createSync(recursive: true);
        final bytes = List<int>.filled(5, 9);
        await File(p.join(legacyLogs.path, 'x.log')).writeAsBytes(bytes);

        final importDir = Directory(
          p.join(
            machineRoot.path,
            MachineStorageLayout.logs,
            MachineStorageLayout.legacyImportedLogsSubdirectory,
          ),
        )..createSync(recursive: true);
        await File(p.join(importDir.path, 'x.log')).writeAsBytes(bytes);

        final r1 = await migrateLegacyUserLogFilesToMachineScopeIfNeeded(
          machineRootOverride: machineRoot,
          legacyAppDataOverride: legacyApp,
        );

        expect(r1.filesCopiedThisRun, 0);
        expect(r1.hadCopyFailures, isFalse);
        final marker = File(
          p.join(
            machineRoot.path,
            MachineStorageLayout.config,
            MachineStorageLayout.legacyAppdataLogsMigrationMarker,
          ),
        );
        expect(await marker.exists(), isTrue);
      },
    );
  });

  group('legacyWindowsProfileFolderLabel', () {
    test('returns folder name after Users segment', () {
      expect(
        legacyWindowsProfileFolderLabel(
          r'C:\Users\Alice\AppData\Roaming\Backup Database',
        ),
        'Alice',
      );
    });

    test('accepts forward slashes in path', () {
      expect(
        legacyWindowsProfileFolderLabel(
          'C:/Users/Bob/AppData/Roaming/Backup Database',
        ),
        'Bob',
      );
    });

    test('returns original path when Users is absent', () {
      const path = r'D:\Backup Database';
      expect(legacyWindowsProfileFolderLabel(path), path);
    });
  });
}
