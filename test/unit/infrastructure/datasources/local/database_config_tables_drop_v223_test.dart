import 'dart:io';

import 'package:backup_database/infrastructure/datasources/local/database_config_tables_drop_v223.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  group('DatabaseConfigTablesDropV223.run', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('drop_v223_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('skips when current version is not 2.2.3', () async {
      var markCalled = false;
      final result = await DatabaseConfigTablesDropV223.run(
        initialWait: Duration.zero,
        appVersionProvider: () async => '2.2.4',
        machineDataDirectoryProvider: () async => tempDir,
        hasAlreadyReset: () async => false,
        markResetCompleted: () async {
          markCalled = true;
        },
      );

      expect(result, isFalse);
      expect(markCalled, isFalse);
    });

    test('skips when version cannot be parsed', () async {
      final result = await DatabaseConfigTablesDropV223.run(
        initialWait: Duration.zero,
        appVersionProvider: () async => 'not-a-semver',
        machineDataDirectoryProvider: () async => tempDir,
        hasAlreadyReset: () async => false,
        markResetCompleted: () async {},
      );

      expect(result, isFalse);
    });

    test('skips when reset was already executed', () async {
      var markCalled = false;
      final result = await DatabaseConfigTablesDropV223.run(
        initialWait: Duration.zero,
        appVersionProvider: () async => '2.2.3',
        machineDataDirectoryProvider: () async => tempDir,
        hasAlreadyReset: () async => true,
        markResetCompleted: () async {
          markCalled = true;
        },
      );

      expect(result, isFalse);
      expect(markCalled, isFalse);
    });

    test('skips when database file does not exist', () async {
      var markCalled = false;
      final result = await DatabaseConfigTablesDropV223.run(
        initialWait: Duration.zero,
        appVersionProvider: () async => '2.2.3',
        machineDataDirectoryProvider: () async => tempDir,
        hasAlreadyReset: () async => false,
        markResetCompleted: () async {
          markCalled = true;
        },
      );

      expect(result, isFalse);
      expect(markCalled, isFalse);
    });

    test(
      'renames and drops config tables, marks reset and recreates pending',
      () async {
        final dbPath = p.join(tempDir.path, 'backup_database.db');
        sqlite3.sqlite3.open(dbPath)
          ..execute('CREATE TABLE sql_server_configs_table (id TEXT)')
          ..execute('CREATE TABLE sybase_configs_table (id TEXT)')
          ..execute('CREATE TABLE postgres_configs_table (id TEXT)')
          ..execute(
            'INSERT INTO sql_server_configs_table (id) VALUES (?)',
            ['keep-me'],
          )
          ..dispose();

        var markCalled = false;
        final result = await DatabaseConfigTablesDropV223.run(
          initialWait: Duration.zero,
          appVersionProvider: () async => '2.2.3+12',
          machineDataDirectoryProvider: () async => tempDir,
          hasAlreadyReset: () async => false,
          markResetCompleted: () async {
            markCalled = true;
          },
        );

        expect(result, isTrue);
        expect(markCalled, isTrue);

        final verifyDb = sqlite3.sqlite3.open(dbPath);
        try {
          final tables = verifyDb
              .select(
                'SELECT name FROM sqlite_master '
                "WHERE type='table' AND name LIKE '%configs_table%'",
              )
              .map((row) => row['name'] as String)
              .toList();

          expect(
            tables,
            isNot(contains('sql_server_configs_table')),
            reason: 'original table should have been dropped',
          );
          expect(
            tables.any(
              (name) =>
                  name.startsWith('sql_server_configs_table_backup_v2_2_3_'),
            ),
            isTrue,
            reason: 'backup snapshot should remain available for rollback',
          );

          final backupTableName = tables.firstWhere(
            (name) =>
                name.startsWith('sql_server_configs_table_backup_v2_2_3_'),
          );
          final rows = verifyDb.select('SELECT id FROM $backupTableName');
          expect(rows.first['id'], equals('keep-me'));
        } finally {
          verifyDb.dispose();
        }
      },
    );
  });
}
