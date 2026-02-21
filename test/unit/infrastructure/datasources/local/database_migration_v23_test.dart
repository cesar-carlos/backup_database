import 'dart:io';

import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('db_migration_v23_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AppDatabase migration v22 -> v23', () {
    test('adds OAuth SMTP columns with safe defaults', () async {
      final file = File(p.join(tempDir.path, 'legacy_v22.db'));
      _createLegacyV22Database(file.path);

      final db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final columns = await db
            .customSelect('PRAGMA table_info(email_configs_table)')
            .get();
        final names = columns.map((row) => row.read<String>('name')).toSet();

        expect(names.contains('auth_mode'), isTrue);
        expect(names.contains('oauth_provider'), isTrue);
        expect(names.contains('oauth_account_email'), isTrue);
        expect(names.contains('oauth_token_key'), isTrue);
        expect(names.contains('oauth_connected_at'), isTrue);
        expect(names.contains('access_token'), isFalse);
        expect(names.contains('refresh_token'), isFalse);

        final row = await db.customSelect('''
          SELECT
            auth_mode,
            oauth_provider,
            oauth_account_email,
            oauth_token_key,
            oauth_connected_at
          FROM email_configs_table
          WHERE id = 'config-1'
        ''').getSingle();

        expect(row.read<String>('auth_mode'), 'password');
        expect(row.read<String?>('oauth_provider'), isNull);
        expect(row.read<String?>('oauth_account_email'), isNull);
        expect(row.read<String?>('oauth_token_key'), isNull);
        expect(row.read<int?>('oauth_connected_at'), isNull);
      } finally {
        await db.close();
      }
    });
  });
}

void _createLegacyV22Database(String path) {
  final sqliteDb = sqlite.sqlite3.open(path);

  sqliteDb.execute('''
    CREATE TABLE email_configs_table (
      id TEXT PRIMARY KEY NOT NULL,
      config_name TEXT NOT NULL DEFAULT 'Configuracao SMTP',
      sender_name TEXT NOT NULL,
      from_email TEXT NOT NULL,
      from_name TEXT NOT NULL,
      smtp_server TEXT NOT NULL,
      smtp_port INTEGER NOT NULL,
      username TEXT NOT NULL,
      password TEXT NOT NULL,
      smtp_password_key TEXT NOT NULL,
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
      config_name,
      sender_name,
      from_email,
      from_name,
      smtp_server,
      smtp_port,
      username,
      password,
      smtp_password_key,
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
      'Configuracao SMTP',
      'Sistema Legacy',
      'legacy@example.com',
      'Sistema Legacy',
      'smtp.legacy.local',
      587,
      'legacy_user',
      '',
      'email_smtp_password_config-1',
      1,
      '[]',
      1,
      1,
      1,
      0,
      1,
      1700000000000,
      1700000000000
    )
  ''');

  sqliteDb.execute('PRAGMA user_version = 22');
  sqliteDb.dispose();
}
