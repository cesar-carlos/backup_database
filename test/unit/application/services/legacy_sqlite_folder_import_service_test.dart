import 'dart:io';

import 'package:backup_database/application/services/legacy_sqlite_folder_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/sqlite_test_helpers.dart';

void main() {
  group('LegacySqliteFolderImportService', () {
    test('copies bundle when machine data dir has no db', () async {
      final tmp = await Directory.systemTemp.createTemp('sqlite_import_test');
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final source = Directory(p.join(tmp.path, 'source'))..createSync();
      final data = Directory(p.join(tmp.path, 'machine', 'data'))
        ..createSync(recursive: true);

      writeMinimalValidSqliteDbFile(
        p.join(source.path, 'backup_database.db'),
      );

      final service = LegacySqliteFolderImportService();
      final result = await service.importFromFolder(
        source,
        machineDataDirectoryOverride: data,
      );

      expect(result.bundlesCopied, 1);
      expect(result.bundlesSkippedDestinationNotEmpty, isEmpty);
      final srcLen = await File(
        p.join(source.path, 'backup_database.db'),
      ).length();
      expect(
        await File(p.join(data.path, 'backup_database.db')).length(),
        srcLen,
      );
    });

    test('skips when destination already has non-empty db', () async {
      final tmp = await Directory.systemTemp.createTemp('sqlite_import_skip');
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final source = Directory(p.join(tmp.path, 'source'))..createSync();
      final data = Directory(p.join(tmp.path, 'machine', 'data'))
        ..createSync(recursive: true);
      writeMinimalValidSqliteDbFile(
        p.join(source.path, 'backup_database.db'),
      );
      await File(
        p.join(data.path, 'backup_database.db'),
      ).writeAsBytes(List<int>.filled(20, 2));

      final service = LegacySqliteFolderImportService();
      final result = await service.importFromFolder(
        source,
        machineDataDirectoryOverride: data,
      );

      expect(result.bundlesCopied, 0);
      expect(
        result.bundlesSkippedDestinationNotEmpty,
        contains('backup_database'),
      );
      expect(await File(p.join(data.path, 'backup_database.db')).length(), 20);
    });

    test('skips source with invalid SQLite header', () async {
      final tmp = await Directory.systemTemp.createTemp('sqlite_import_hdr');
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });

      final source = Directory(p.join(tmp.path, 'source'))..createSync();
      final data = Directory(p.join(tmp.path, 'machine', 'data'))
        ..createSync(recursive: true);
      await File(
        p.join(source.path, 'backup_database.db'),
      ).writeAsBytes(List<int>.filled(64, 9));

      final service = LegacySqliteFolderImportService();
      final result = await service.importFromFolder(
        source,
        machineDataDirectoryOverride: data,
      );

      expect(result.bundlesCopied, 0);
      expect(
        result.bundlesSkippedInvalidSqliteHeader,
        contains('backup_database'),
      );
    });
  });
}
