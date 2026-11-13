import 'dart:io';

import 'package:backup_database/core/config/execution_ownership.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
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
