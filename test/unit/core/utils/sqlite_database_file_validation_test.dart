import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/utils/sqlite_database_file_validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/sqlite_test_helpers.dart';

void main() {
  group('sqliteHeaderBytesAreValid', () {
    test('accepts standard SQLite 3 header', () {
      final bytes = Uint8List.fromList(<int>[
        ...'SQLite format 3'.codeUnits,
        0,
      ]);
      expect(sqliteHeaderBytesAreValid(bytes), isTrue);
    });

    test('rejects wrong magic', () {
      final bytes = Uint8List.fromList(List<int>.filled(16, 65));
      expect(sqliteHeaderBytesAreValid(bytes), isFalse);
    });
  });

  group('sqliteDatabaseFileHasValidHeader', () {
    test('true for minimal sqlite file', () async {
      final tmp = await Directory.systemTemp.createTemp('sqlite_hdr');
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });
      final f = p.join(tmp.path, 'a.db');
      writeMinimalValidSqliteDbFile(f);
      expect(await sqliteDatabaseFileHasValidHeader(File(f)), isTrue);
    });

    test('false for random bytes', () async {
      final tmp = await Directory.systemTemp.createTemp('sqlite_hdr_bad');
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });
      final f = File(p.join(tmp.path, 'b.db'));
      await f.writeAsBytes(List<int>.filled(32, 7));
      expect(await sqliteDatabaseFileHasValidHeader(f), isFalse);
    });
  });

  group('sqliteDatabaseQuickCheckFile', () {
    test('returns ok for valid database', () async {
      final tmp = await Directory.systemTemp.createTemp('sqlite_qc');
      addTearDown(() async {
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      });
      final f = p.join(tmp.path, 'c.db');
      writeMinimalValidSqliteDbFile(f);
      expect(
        await sqliteDatabaseQuickCheckFile(File(f)),
        SqliteQuickCheckResult.ok,
      );
    });
  });
}
