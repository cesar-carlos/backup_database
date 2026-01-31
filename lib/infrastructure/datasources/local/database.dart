import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/datasources/daos/daos.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    SqlServerConfigsTable,
    SybaseConfigsTable,
    PostgresConfigsTable,
    BackupDestinationsTable,
    SchedulesTable,
    BackupHistoryTable,
    BackupLogsTable,
    EmailConfigsTable,
    LicensesTable,
  ],
  daos: [
    SqlServerConfigDao,
    SybaseConfigDao,
    PostgresConfigDao,
    BackupDestinationDao,
    ScheduleDao,
    BackupHistoryDao,
    BackupLogDao,
    EmailConfigDao,
    LicenseDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        await _ensureSybaseConfigsTableExists(m);

        if (from < 2) {
          try {
            final columns = await customSelect(
              'PRAGMA table_info(sybase_configs)',
            ).get();
            final hasPortColumn = columns.any(
              (row) => row.data['name'] == 'port',
            );

            if (!hasPortColumn) {
              await m.addColumn(sybaseConfigsTable, sybaseConfigsTable.port);
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro ao verificar/adicionar coluna port',
              e,
              stackTrace,
            );
          }
        }

        if (from < 3) {
          try {
            final columns = await customSelect(
              'PRAGMA table_info(sybase_configs)',
            ).get();
            final hasDatabaseNameColumn = columns.any(
              (row) => row.data['name'] == 'database_name',
            );

            if (!hasDatabaseNameColumn) {
              await m.addColumn(
                sybaseConfigsTable,
                sybaseConfigsTable.databaseName,
              );

              await customStatement(
                'UPDATE sybase_configs SET database_name = server_name '
                "WHERE database_name IS NULL OR database_name = ''",
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro ao verificar/adicionar coluna database_name',
              e,
              stackTrace,
            );
          }
        }

        if (from < 4) {
          try {
            final columns = await customSelect(
              'PRAGMA table_info(email_configs_table)',
            ).get();
            final columnNames = columns
                .map((row) => row.data['name'] as String)
                .toSet();

            if (!columnNames.contains('from_email')) {
              await customStatement(
                'ALTER TABLE email_configs_table ADD COLUMN from_email TEXT',
              );
            }
            if (!columnNames.contains('from_name')) {
              await customStatement(
                'ALTER TABLE email_configs_table ADD COLUMN from_name TEXT',
              );
            }
            if (!columnNames.contains('smtp_server')) {
              await customStatement(
                'ALTER TABLE email_configs_table ADD COLUMN smtp_server TEXT',
              );
            }
            if (!columnNames.contains('smtp_port')) {
              await customStatement(
                'ALTER TABLE email_configs_table ADD COLUMN smtp_port INTEGER',
              );
            }
            if (!columnNames.contains('username')) {
              await customStatement(
                'ALTER TABLE email_configs_table ADD COLUMN username TEXT',
              );
            }
            if (!columnNames.contains('password')) {
              await customStatement(
                'ALTER TABLE email_configs_table ADD COLUMN password TEXT',
              );
            }
            if (!columnNames.contains('use_ssl')) {
              await customStatement(
                'ALTER TABLE email_configs_table ADD COLUMN use_ssl INTEGER',
              );
            }

            LoggerService.info(
              'Colunas de SMTP adicionadas à tabela email_configs_table',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro ao adicionar colunas de SMTP na tabela email_configs_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 5) {
          try {
            await customStatement('''
              UPDATE email_configs_table 
              SET 
                sender_name = COALESCE(sender_name, 'Sistema de Backup'),
                from_email = COALESCE(from_email, 'backup@example.com'),
                from_name = COALESCE(from_name, 'Sistema de Backup'),
                smtp_server = COALESCE(smtp_server, 'smtp.gmail.com'),
                smtp_port = COALESCE(smtp_port, 587),
                username = COALESCE(username, ''),
                password = COALESCE(password, ''),
                use_ssl = COALESCE(use_ssl, 1),
                recipients = COALESCE(recipients, '[]'),
                notify_on_success = COALESCE(notify_on_success, 1),
                notify_on_error = COALESCE(notify_on_error, 1),
                notify_on_warning = COALESCE(notify_on_warning, 1),
                attach_log = COALESCE(attach_log, 0),
                enabled = COALESCE(enabled, 1)
              WHERE 
                sender_name IS NULL 
                OR from_email IS NULL 
                OR from_name IS NULL 
                OR smtp_server IS NULL 
                OR smtp_port IS NULL 
                OR username IS NULL 
                OR password IS NULL 
                OR use_ssl IS NULL
                OR recipients IS NULL
                OR notify_on_success IS NULL
                OR notify_on_error IS NULL
                OR notify_on_warning IS NULL
                OR attach_log IS NULL
                OR enabled IS NULL
            ''');
            LoggerService.info(
              'Migração v5: Valores padrão atualizados em email_configs_table',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v5 para email_configs_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 6) {
          try {
            final columns = await customSelect(
              'PRAGMA table_info(schedules_table)',
            ).get();
            final hasBackupFolderColumn = columns.any(
              (row) => row.data['name'] == 'backup_folder',
            );

            if (!hasBackupFolderColumn) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN backup_folder '
                "TEXT NOT NULL DEFAULT ''",
              );
              LoggerService.info(
                'Migração v6: Coluna backup_folder adicionada à '
                'schedules_table',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v6 para schedules_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 7) {
          try {
            final schedulesColumns = await customSelect(
              'PRAGMA table_info(schedules_table)',
            ).get();
            final hasSchedulesBackupTypeColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'backup_type',
            );

            if (!hasSchedulesBackupTypeColumn) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN backup_type '
                "TEXT NOT NULL DEFAULT 'full'",
              );
              LoggerService.info(
                'Migração v7: Coluna backup_type adicionada à '
                'schedules_table',
              );
            }

            final historyColumns = await customSelect(
              'PRAGMA table_info(backup_history_table)',
            ).get();
            final hasHistoryBackupTypeColumn = historyColumns.any(
              (row) => row.data['name'] == 'backup_type',
            );

            if (!hasHistoryBackupTypeColumn) {
              await customStatement(
                'ALTER TABLE backup_history_table ADD COLUMN backup_type '
                "TEXT NOT NULL DEFAULT 'full'",
              );
              LoggerService.info(
                'Migração v7: Coluna backup_type adicionada à '
                'backup_history_table',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v7 para backup_type',
              e,
              stackTrace,
            );
          }
        }

        if (from < 8) {
          try {
            final schedulesColumns = await customSelect(
              'PRAGMA table_info(schedules_table)',
            ).get();
            final hasTruncateLogColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'truncate_log',
            );

            if (!hasTruncateLogColumn) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN truncate_log '
                'INTEGER NOT NULL DEFAULT 1',
              );
              LoggerService.info(
                'Migração v8: Coluna truncate_log adicionada à '
                'schedules_table',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v8 para truncate_log',
              e,
              stackTrace,
            );
          }
        }

        if (from < 9) {
          try {
            final schedulesColumns = await customSelect(
              'PRAGMA table_info(schedules_table)',
            ).get();
            final hasPostBackupScriptColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'post_backup_script',
            );

            if (!hasPostBackupScriptColumn) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN '
                'post_backup_script TEXT',
              );
              LoggerService.info(
                'Migração v9: Coluna post_backup_script adicionada à '
                'schedules_table',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v9 para post_backup_script',
              e,
              stackTrace,
            );
          }
        }

        if (from < 10) {
          try {
            final schedulesColumns = await customSelect(
              'PRAGMA table_info(schedules_table)',
            ).get();
            final hasEnableChecksumColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'enable_checksum',
            );
            final hasVerifyAfterBackupColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'verify_after_backup',
            );

            if (!hasEnableChecksumColumn) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN enable_checksum '
                'INTEGER NOT NULL DEFAULT 0',
              );
              LoggerService.info(
                'Migração v10: Coluna enable_checksum adicionada à '
                'schedules_table',
              );
            }

            if (!hasVerifyAfterBackupColumn) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN verify_after_backup '
                'INTEGER NOT NULL DEFAULT 0',
              );
              LoggerService.info(
                'Migração v10: Coluna verify_after_backup adicionada à '
                'schedules_table',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v10 para enable_checksum e '
              'verify_after_backup',
              e,
              stackTrace,
            );
          }
        }

        if (from < 11) {
          try {
            final tables = await customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name='postgres_configs_table'",
            ).get();
            final hasTable = tables.isNotEmpty;

            if (!hasTable) {
              await customStatement('''
                CREATE TABLE postgres_configs_table (
                  id TEXT PRIMARY KEY,
                  name TEXT NOT NULL,
                  host TEXT NOT NULL,
                  port INTEGER NOT NULL DEFAULT 5432,
                  database TEXT NOT NULL,
                  username TEXT NOT NULL,
                  password TEXT NOT NULL,
                  enabled INTEGER NOT NULL DEFAULT 1,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL
                )
              ''');
              LoggerService.info(
                'Migração v11: Tabela postgres_configs_table criada',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v11 para postgres_configs_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 12) {
          try {
            final columns = await customSelect(
              'PRAGMA table_info(schedules_table)',
            ).get();
            final hasCompressionFormatColumn = columns.any(
              (row) => row.data['name'] == 'compression_format',
            );

            if (!hasCompressionFormatColumn) {
              await m.addColumn(
                schedulesTable,
                schedulesTable.compressionFormat,
              );

              await customStatement(
                'UPDATE schedules_table SET compression_format = CASE '
                "WHEN compress_backup = 0 THEN 'none' "
                "ELSE 'zip' END",
              );

              LoggerService.info(
                'Coluna compression_format adicionada à tabela schedules_table',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro ao verificar/adicionar coluna compression_format',
              e,
              stackTrace,
            );
          }
        }

        if (from < 13) {
          try {
            final tables = await customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name='licenses_table'",
            ).get();
            final hasTable = tables.isNotEmpty;

            if (!hasTable) {
              await m.createTable(licensesTable);
              LoggerService.info(
                'Migração v13: Tabela licenses_table criada com sucesso.',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v13 para licenses_table',
              e,
              stackTrace,
            );
          }
        }
      },
      beforeOpen: (details) async {
        await _ensureSybaseConfigsTableExistsDirect();

        await _migrateSybaseColumnsToSnakeCase();

        await _ensureEmailConfigsColumnsExist();
      },
    );
  }

  Future<void> _ensureSybaseConfigsTableExists(Migrator m) async {
    try {
      final tableExists = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='sybase_configs'",
      ).getSingleOrNull();

      if (tableExists == null) {
        LoggerService.info('Criando tabela sybase_configs...');
        await m.createTable(sybaseConfigsTable);
        LoggerService.info('Tabela sybase_configs criada com sucesso');
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao verificar/criar tabela sybase_configs',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _ensureSybaseConfigsTableExistsDirect() async {
    try {
      final tableExists = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='sybase_configs'",
      ).getSingleOrNull();

      if (tableExists == null) {
        LoggerService.info(
          'Tabela sybase_configs não existe, criando via SQL.',
        );
        await customStatement('''
          CREATE TABLE IF NOT EXISTS sybase_configs (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            server_name TEXT NOT NULL,
            database_name TEXT NOT NULL DEFAULT '',
            database_file TEXT NOT NULL DEFAULT '',
            port INTEGER NOT NULL DEFAULT 2638,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        LoggerService.info('Tabela sybase_configs criada com sucesso via SQL');
      }
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao criar tabela sybase_configs', e, stackTrace);
    }
  }

  Future<void> _migrateSybaseColumnsToSnakeCase() async {
    try {
      final columns = await customSelect(
        'PRAGMA table_info(sybase_configs)',
      ).get();

      final columnNames = columns
          .map((row) => row.data['name'] as String)
          .toSet();

      final hasCamelCaseColumns =
          columnNames.contains('serverName') ||
          columnNames.contains('databaseName') ||
          columnNames.contains('createdAt');

      final hasSnakeCaseColumns =
          columnNames.contains('server_name') ||
          columnNames.contains('database_name') ||
          columnNames.contains('created_at');

      if (hasCamelCaseColumns && !hasSnakeCaseColumns) {
        LoggerService.info(
          'Migrando colunas sybase_configs de camelCase para snake_case...',
        );

        await customStatement('''
          CREATE TABLE sybase_configs_new (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            server_name TEXT NOT NULL,
            database_name TEXT NOT NULL DEFAULT '',
            database_file TEXT NOT NULL DEFAULT '',
            port INTEGER NOT NULL DEFAULT 2638,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await customStatement('''
          INSERT INTO sybase_configs_new (
            id, name, server_name, database_name, database_file, port,
            username, password, enabled, created_at, updated_at
          )
          SELECT 
            id, name, serverName, 
            COALESCE(databaseName, serverName, ''),
            COALESCE(databaseFile, ''),
            COALESCE(port, 2638),
            username, password,
            COALESCE(enabled, 1),
            createdAt, updatedAt
          FROM sybase_configs
        ''');

        await customStatement('DROP TABLE sybase_configs');
        await customStatement(
          'ALTER TABLE sybase_configs_new RENAME TO sybase_configs',
        );

        LoggerService.info(
          'Migração de colunas sybase_configs concluída com sucesso',
        );
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao migrar colunas sybase_configs para snake_case',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _ensureEmailConfigsColumnsExist() async {
    try {
      final tableExists = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='email_configs_table'",
      ).getSingleOrNull();

      if (tableExists == null) {
        return;
      }

      final columns = await customSelect(
        'PRAGMA table_info(email_configs_table)',
      ).get();
      final columnNames = columns
          .map((row) => row.data['name'] as String)
          .toSet();

      final expectedColumns = {
        'id',
        'sender_name',
        'from_email',
        'from_name',
        'smtp_server',
        'smtp_port',
        'username',
        'password',
        'use_ssl',
        'recipients',
        'notify_on_success',
        'notify_on_error',
        'notify_on_warning',
        'attach_log',
        'enabled',
        'created_at',
        'updated_at',
      };

      final obsoleteColumns = columnNames
          .where((col) => !expectedColumns.contains(col))
          .toList();

      if (obsoleteColumns.isNotEmpty) {
        LoggerService.info(
          'Colunas obsoletas em email_configs_table: '
          '${obsoleteColumns.join(", ")}',
        );
      }

      if (!columnNames.contains('from_email')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN from_email TEXT',
        );
        LoggerService.info(
          'Coluna from_email adicionada à email_configs_table',
        );
      }
      if (!columnNames.contains('from_name')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN from_name TEXT',
        );
        LoggerService.info('Coluna from_name adicionada à email_configs_table');
      }
      if (!columnNames.contains('smtp_server')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN smtp_server TEXT',
        );
        LoggerService.info(
          'Coluna smtp_server adicionada à email_configs_table',
        );
      }
      if (!columnNames.contains('smtp_port')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN smtp_port INTEGER',
        );
        LoggerService.info('Coluna smtp_port adicionada à email_configs_table');
      }
      if (!columnNames.contains('username')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN username TEXT',
        );
        LoggerService.info('Coluna username adicionada à email_configs_table');
      }
      if (!columnNames.contains('password')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN password TEXT',
        );
        LoggerService.info('Coluna password adicionada à email_configs_table');
      }
      if (!columnNames.contains('use_ssl')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN use_ssl INTEGER',
        );
        LoggerService.info('Coluna use_ssl adicionada à email_configs_table');
      }

      try {
        const tableName = 'email_configs_table';
        await customStatement('''
          UPDATE $tableName 
          SET 
            sender_name = COALESCE(sender_name, 'Sistema de Backup'),
            from_email = COALESCE(from_email, 'backup@example.com'),
            from_name = COALESCE(from_name, 'Sistema de Backup'),
            smtp_server = COALESCE(smtp_server, 'smtp.gmail.com'),
            smtp_port = COALESCE(smtp_port, 587),
            username = COALESCE(username, ''),
            password = COALESCE(password, ''),
            use_ssl = COALESCE(use_ssl, 1),
            recipients = COALESCE(recipients, '[]'),
            notify_on_success = COALESCE(notify_on_success, 1),
            notify_on_error = COALESCE(notify_on_error, 1),
            notify_on_warning = COALESCE(notify_on_warning, 1),
            attach_log = COALESCE(attach_log, 0),
            enabled = COALESCE(enabled, 1)
          WHERE 
            sender_name IS NULL 
            OR from_email IS NULL 
            OR from_name IS NULL 
            OR smtp_server IS NULL 
            OR smtp_port IS NULL 
            OR username IS NULL 
            OR password IS NULL 
            OR use_ssl IS NULL
            OR recipients IS NULL
            OR notify_on_success IS NULL
            OR notify_on_error IS NULL
            OR notify_on_warning IS NULL
            OR attach_log IS NULL
            OR enabled IS NULL
        ''');
        LoggerService.info(
          'Valores padrão atualizados em email_configs_table.',
        );
      } on Object catch (e, stackTrace) {
        LoggerService.warning(
          'Erro ao atualizar valores padrão em email_configs_table',
          e,
          stackTrace,
        );
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao verificar/adicionar colunas em email_configs',
        e,
        stackTrace,
      );
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'backup_database.db'));
    return NativeDatabase.createInBackground(file);
  });
}
