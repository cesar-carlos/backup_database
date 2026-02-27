import 'dart:io';

import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('db_migration_v25_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AppDatabase migration v24 -> v25', () {
    test(
      'removes duplicate licenses by device_key and creates unique index',
      () async {
        final file = File(p.join(tempDir.path, 'legacy_v24_licenses.db'));
        _createLegacyV24DatabaseWithDuplicateLicenses(file.path);

        final db = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final rows = await db.customSelect(
            'SELECT id, device_key, updated_at FROM licenses_table '
            'ORDER BY device_key, updated_at',
          ).get();

          expect(rows.length, 2);
          expect(rows[0].read<String>('device_key'), 'device-a');
          expect(rows[0].read<String>('id'), 'keep-a');
          expect(rows[1].read<String>('device_key'), 'device-b');
          expect(rows[1].read<String>('id'), 'keep-b');

          final indexRows = await db.customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='idx_licenses_device_key'",
          ).get();

          expect(indexRows.length, 1);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'unique index prevents duplicate device_key on insert',
      () async {
        final file = File(p.join(tempDir.path, 'legacy_v24_licenses_2.db'));
        _createLegacyV24DatabaseWithDuplicateLicenses(file.path);

        final db = AppDatabase.forTesting(NativeDatabase(file));
        try {
          await db.customStatement('''
            INSERT INTO licenses_table (
              id, device_key, license_key, allowed_features,
              created_at, updated_at
            ) VALUES (
              'duplicate-id', 'device-a', 'key', '[]',
              1700000000000000, 1700000000000000
            )
          ''');

          fail('Insert should have failed due to unique constraint');
        } on Object catch (e) {
          expect(
            e.toString(),
            anyOf(contains('UNIQUE'), contains('constraint')),
          );
        } finally {
          await db.close();
        }
      },
    );
  });
}

void _createLegacyV24DatabaseWithDuplicateLicenses(String path) {
  final sqliteDb = sqlite.sqlite3.open(path);

  sqliteDb.execute('''
    CREATE TABLE licenses_table (
      id TEXT PRIMARY KEY NOT NULL,
      device_key TEXT NOT NULL,
      license_key TEXT NOT NULL,
      expires_at INTEGER,
      allowed_features TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  sqliteDb.execute('''
    INSERT INTO licenses_table (
      id, device_key, license_key, allowed_features,
      created_at, updated_at
    ) VALUES
    ('drop-a', 'device-a', 'old-key', '[]', 1700000000000000, 1700000000000000),
    ('keep-a', 'device-a', 'new-key', '["f1"]', 1700000000000000, 1700000100000000),
    ('keep-b', 'device-b', 'key-b', '[]', 1700000000000000, 1700000200000000)
  ''');

  sqliteDb.execute('PRAGMA user_version = 24');
  sqliteDb.dispose();
}
