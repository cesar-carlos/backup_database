import 'dart:io';

import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('db_migration_v19_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AppDatabase migration v18 -> v20', () {
    test(
      'adds config_name, backfills targets and cleans legacy notification fields',
      () async {
        final file = File(p.join(tempDir.path, 'legacy_v18_a.db'));
        _createLegacyV18Database(file.path);

        final db = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final columns = await db
              .customSelect(
                'PRAGMA table_info(email_configs_table)',
              )
              .get();
          final columnNames = columns
              .map((row) => row.read<String>('name'))
              .toSet();
          expect(columnNames.contains('config_name'), isTrue);

          final configRows = await db.customSelect('''
          SELECT
            smtp_server,
            smtp_port,
            username,
            password,
            recipients,
            notify_on_success,
            notify_on_error,
            notify_on_warning
          FROM email_configs_table
          WHERE id = 'config-1'
        ''').getSingle();

          expect(configRows.read<String>('smtp_server'), 'smtp.legacy.local');
          expect(configRows.read<int>('smtp_port'), 2525);
          expect(configRows.read<String>('username'), 'legacy_user');
          expect(configRows.read<String>('password'), 'legacy_pass');
          expect(
            configRows.read<String>('recipients'),
            '[]',
          );
          expect(configRows.read<int>('notify_on_success'), 1);
          expect(configRows.read<int>('notify_on_error'), 1);
          expect(configRows.read<int>('notify_on_warning'), 1);

          final targetRows = await db.customSelect('''
          SELECT recipient_email, notify_on_success, notify_on_error, notify_on_warning
          FROM email_notification_targets_table
          WHERE email_config_id = 'config-1'
          ORDER BY recipient_email
        ''').get();

          expect(targetRows.length, 2);
          expect(
            targetRows[0].read<String>('recipient_email'),
            'a@exemplo.com',
          );
          expect(
            targetRows[1].read<String>('recipient_email'),
            'b@exemplo.com',
          );
          expect(targetRows[0].read<int>('notify_on_success'), 1);
          expect(targetRows[0].read<int>('notify_on_error'), 0);
          expect(targetRows[0].read<int>('notify_on_warning'), 1);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'keeps backfill idempotent with preexisting target and enforces cascade delete',
      () async {
        final file = File(p.join(tempDir.path, 'legacy_v18_b.db'));
        _createLegacyV18Database(
          file.path,
          createTargetTableBeforeUpgrade: true,
          preexistingTargetRecipient: 'a@exemplo.com',
        );

        final db = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final targetRows = await db.customSelect('''
          SELECT recipient_email
          FROM email_notification_targets_table
          WHERE email_config_id = 'config-1'
          ORDER BY recipient_email
        ''').get();

          expect(targetRows.length, 2);
          expect(
            targetRows
                .map((row) => row.read<String>('recipient_email'))
                .toList(),
            ['a@exemplo.com', 'b@exemplo.com'],
          );

          await db.customStatement(
            'DELETE FROM email_configs_table WHERE id = ?',
            ['config-1'],
          );

          final afterDeleteRows = await db
              .customSelect(
                'SELECT id FROM email_notification_targets_table WHERE email_config_id = ?',
                variables: [Variable.withString('config-1')],
              )
              .get();

          expect(afterDeleteRows, isEmpty);
        } finally {
          await db.close();
        }
      },
    );
  });
}

void _createLegacyV18Database(
  String path, {
  bool createTargetTableBeforeUpgrade = false,
  String? preexistingTargetRecipient,
}) {
  final sqliteDb = sqlite.sqlite3.open(path);

  sqliteDb.execute('''
    CREATE TABLE email_configs_table (
      id TEXT PRIMARY KEY NOT NULL,
      sender_name TEXT NOT NULL,
      from_email TEXT NOT NULL,
      from_name TEXT NOT NULL,
      smtp_server TEXT NOT NULL,
      smtp_port INTEGER NOT NULL,
      username TEXT NOT NULL,
      password TEXT NOT NULL,
      use_ssl INTEGER NOT NULL,
      recipients TEXT NOT NULL,
      notify_on_success INTEGER NOT NULL,
      notify_on_error INTEGER NOT NULL,
      notify_on_warning INTEGER NOT NULL,
      attach_log INTEGER NOT NULL,
      enabled INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  sqliteDb.execute('''
    INSERT INTO email_configs_table (
      id,
      sender_name,
      from_email,
      from_name,
      smtp_server,
      smtp_port,
      username,
      password,
      use_ssl,
      recipients,
      notify_on_success,
      notify_on_error,
      notify_on_warning,
      attach_log,
      enabled,
      created_at,
      updated_at
    ) VALUES (
      'config-1',
      'Sistema Legacy',
      'legacy@example.com',
      'Sistema Legacy',
      'smtp.legacy.local',
      2525,
      'legacy_user',
      'legacy_pass',
      0,
      '["a@exemplo.com","b@exemplo.com"]',
      1,
      0,
      1,
      0,
      1,
      1700000000000,
      1700000000000
    )
  ''');

  if (createTargetTableBeforeUpgrade) {
    sqliteDb.execute('''
      CREATE TABLE email_notification_targets_table (
        id TEXT PRIMARY KEY NOT NULL,
        email_config_id TEXT NOT NULL,
        recipient_email TEXT NOT NULL,
        notify_on_success INTEGER NOT NULL DEFAULT 1,
        notify_on_error INTEGER NOT NULL DEFAULT 1,
        notify_on_warning INTEGER NOT NULL DEFAULT 1,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(email_config_id, recipient_email),
        FOREIGN KEY(email_config_id) REFERENCES email_configs_table(id)
          ON DELETE CASCADE
      )
    ''');

    sqliteDb.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_notification_targets_config_id
      ON email_notification_targets_table(email_config_id)
    ''');

    if (preexistingTargetRecipient != null) {
      sqliteDb.execute('''
        INSERT INTO email_notification_targets_table (
          id,
          email_config_id,
          recipient_email,
          notify_on_success,
          notify_on_error,
          notify_on_warning,
          enabled,
          created_at,
          updated_at
        ) VALUES (
          'config-1:$preexistingTargetRecipient',
          'config-1',
          '$preexistingTargetRecipient',
          1,
          0,
          1,
          1,
          1700000000000,
          1700000000000
        )
      ''');
    }
  }

  sqliteDb.execute('PRAGMA user_version = 18');
  sqliteDb.dispose();
}
