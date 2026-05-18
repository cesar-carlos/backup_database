import 'dart:io';

import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('db_migration_v32_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AppDatabase migration v31 -> v32 (Firebird configs)', () {
    test(
      'recreates firebird_configs_table when missing at user_version 31',
      () async {
        final file = File(p.join(tempDir.path, 'legacy_v31_no_firebird.db'));

        final dbBootstrap = AppDatabase.forTesting(NativeDatabase(file));
        await dbBootstrap.close();

        final dbDowngrade = AppDatabase.forTesting(NativeDatabase(file));
        try {
          await dbDowngrade.customStatement(
            'DROP TABLE IF EXISTS firebird_configs_table',
          );
          await dbDowngrade.customStatement('PRAGMA user_version = 31');
        } finally {
          await dbDowngrade.close();
        }

        final dbMigrated = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final versionRow = await dbMigrated
              .customSelect('PRAGMA user_version')
              .getSingle();
          expect(versionRow.read<int>('user_version'), 33);

          final tableRows = await dbMigrated
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name='firebird_configs_table'",
              )
              .get();
          expect(tableRows.length, 1);

          final columns = await dbMigrated
              .customSelect('PRAGMA table_info(firebird_configs_table)')
              .get();
          final columnNames = columns
              .map((row) => row.read<String>('name'))
              .toSet();
          expect(columnNames.contains('id'), isTrue);
          expect(columnNames.contains('name'), isTrue);
          expect(columnNames.contains('host'), isTrue);
          expect(columnNames.contains('database_file'), isTrue);
        } finally {
          await dbMigrated.close();
        }
      },
    );
  });
}
