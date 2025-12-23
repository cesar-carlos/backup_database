import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/logger_service.dart';
import 'tables/tables.dart';
import '../daos/daos.dart';

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
        // Sempre garantir que a tabela sybase_configs existe
        await _ensureSybaseConfigsTableExists(m);

        if (from < 2) {
          // Adicionar coluna port se não existir
          try {
            final columns = await (customSelect(
              "PRAGMA table_info(sybase_configs)",
            ).get());
            final hasPortColumn = columns.any(
              (row) => row.data['name'] == 'port',
            );

            if (!hasPortColumn) {
              await m.addColumn(sybaseConfigsTable, sybaseConfigsTable.port);
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro ao verificar/adicionar coluna port',
              e,
              stackTrace,
            );
          }
        }

        if (from < 3) {
          // Adicionar coluna database_name na tabela sybase_configs
          try {
            final columns = await (customSelect(
              "PRAGMA table_info(sybase_configs)",
            ).get());
            final hasDatabaseNameColumn = columns.any(
              (row) => row.data['name'] == 'database_name',
            );

            if (!hasDatabaseNameColumn) {
              await m.addColumn(
                sybaseConfigsTable,
                sybaseConfigsTable.databaseName,
              );

              // Preencher database_name com server_name para registros existentes
              await customStatement(
                "UPDATE sybase_configs SET database_name = server_name WHERE database_name IS NULL OR database_name = ''",
              );
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro ao verificar/adicionar coluna database_name',
              e,
              stackTrace,
            );
          }
        }

        if (from < 4) {
          // Adicionar colunas de SMTP na tabela email_configs
          try {
            final columns = await (customSelect(
              "PRAGMA table_info(email_configs_table)",
            ).get());
            final columnNames = columns
                .map((row) => row.data['name'] as String)
                .toSet();

            if (!columnNames.contains('from_email')) {
              await customStatement(
                "ALTER TABLE email_configs_table ADD COLUMN from_email TEXT",
              );
            }
            if (!columnNames.contains('from_name')) {
              await customStatement(
                "ALTER TABLE email_configs_table ADD COLUMN from_name TEXT",
              );
            }
            if (!columnNames.contains('smtp_server')) {
              await customStatement(
                "ALTER TABLE email_configs_table ADD COLUMN smtp_server TEXT",
              );
            }
            if (!columnNames.contains('smtp_port')) {
              await customStatement(
                "ALTER TABLE email_configs_table ADD COLUMN smtp_port INTEGER",
              );
            }
            if (!columnNames.contains('username')) {
              await customStatement(
                "ALTER TABLE email_configs_table ADD COLUMN username TEXT",
              );
            }
            if (!columnNames.contains('password')) {
              await customStatement(
                "ALTER TABLE email_configs_table ADD COLUMN password TEXT",
              );
            }
            if (!columnNames.contains('use_ssl')) {
              await customStatement(
                "ALTER TABLE email_configs_table ADD COLUMN use_ssl INTEGER",
              );
            }

            LoggerService.info(
              'Colunas de SMTP adicionadas à tabela email_configs_table',
            );
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro ao adicionar colunas de SMTP na tabela email_configs_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 5) {
          // Migração para versão 5: Garantir que todos os campos têm valores padrão
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
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v5 para email_configs_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 6) {
          // Migração para versão 6: Adicionar coluna backup_folder na tabela schedules
          try {
            final columns = await (customSelect(
              "PRAGMA table_info(schedules_table)",
            ).get());
            final hasBackupFolderColumn = columns.any(
              (row) => row.data['name'] == 'backup_folder',
            );

            if (!hasBackupFolderColumn) {
              await customStatement(
                "ALTER TABLE schedules_table ADD COLUMN backup_folder TEXT NOT NULL DEFAULT ''",
              );
              LoggerService.info(
                'Migração v6: Coluna backup_folder adicionada à schedules_table',
              );
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v6 para schedules_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 7) {
          // Migração para versão 7: Adicionar coluna backup_type nas tabelas schedules e backup_history
          try {
            // Adicionar backup_type em schedules_table
            final schedulesColumns = await (customSelect(
              "PRAGMA table_info(schedules_table)",
            ).get());
            final hasSchedulesBackupTypeColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'backup_type',
            );

            if (!hasSchedulesBackupTypeColumn) {
              await customStatement(
                "ALTER TABLE schedules_table ADD COLUMN backup_type TEXT NOT NULL DEFAULT 'full'",
              );
              LoggerService.info(
                'Migração v7: Coluna backup_type adicionada à schedules_table',
              );
            }

            // Adicionar backup_type em backup_history_table
            final historyColumns = await (customSelect(
              "PRAGMA table_info(backup_history_table)",
            ).get());
            final hasHistoryBackupTypeColumn = historyColumns.any(
              (row) => row.data['name'] == 'backup_type',
            );

            if (!hasHistoryBackupTypeColumn) {
              await customStatement(
                "ALTER TABLE backup_history_table ADD COLUMN backup_type TEXT NOT NULL DEFAULT 'full'",
              );
              LoggerService.info(
                'Migração v7: Coluna backup_type adicionada à backup_history_table',
              );
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v7 para backup_type',
              e,
              stackTrace,
            );
          }
        }

        if (from < 8) {
          // Migração para versão 8: adicionar truncate_log em schedules_table
          try {
            final schedulesColumns = await (customSelect(
              "PRAGMA table_info(schedules_table)",
            ).get());
            final hasTruncateLogColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'truncate_log',
            );

            if (!hasTruncateLogColumn) {
              await customStatement(
                "ALTER TABLE schedules_table ADD COLUMN truncate_log INTEGER NOT NULL DEFAULT 1",
              );
              LoggerService.info(
                'Migração v8: Coluna truncate_log adicionada à schedules_table',
              );
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v8 para truncate_log',
              e,
              stackTrace,
            );
          }
        }

        if (from < 9) {
          // Migração para versão 9: adicionar post_backup_script em schedules_table
          try {
            final schedulesColumns = await (customSelect(
              "PRAGMA table_info(schedules_table)",
            ).get());
            final hasPostBackupScriptColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'post_backup_script',
            );

            if (!hasPostBackupScriptColumn) {
              await customStatement(
                "ALTER TABLE schedules_table ADD COLUMN post_backup_script TEXT",
              );
              LoggerService.info(
                'Migração v9: Coluna post_backup_script adicionada à schedules_table',
              );
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v9 para post_backup_script',
              e,
              stackTrace,
            );
          }
        }

        if (from < 10) {
          // Migração para versão 10: adicionar enable_checksum e verify_after_backup em schedules_table
          try {
            final schedulesColumns = await (customSelect(
              "PRAGMA table_info(schedules_table)",
            ).get());
            final hasEnableChecksumColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'enable_checksum',
            );
            final hasVerifyAfterBackupColumn = schedulesColumns.any(
              (row) => row.data['name'] == 'verify_after_backup',
            );

            if (!hasEnableChecksumColumn) {
              await customStatement(
                "ALTER TABLE schedules_table ADD COLUMN enable_checksum INTEGER NOT NULL DEFAULT 0",
              );
              LoggerService.info(
                'Migração v10: Coluna enable_checksum adicionada à schedules_table',
              );
            }

            if (!hasVerifyAfterBackupColumn) {
              await customStatement(
                "ALTER TABLE schedules_table ADD COLUMN verify_after_backup INTEGER NOT NULL DEFAULT 0",
              );
              LoggerService.info(
                'Migração v10: Coluna verify_after_backup adicionada à schedules_table',
              );
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v10 para enable_checksum e verify_after_backup',
              e,
              stackTrace,
            );
          }
        }

        if (from < 11) {
          // Migração para versão 11: criar tabela postgres_configs_table
          try {
            final tables = await (customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='postgres_configs_table'",
            ).get());
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
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v11 para postgres_configs_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 12) {
          try {
            final columns = await (customSelect(
              "PRAGMA table_info(schedules_table)",
            ).get());
            final hasCompressionFormatColumn = columns.any(
              (row) => row.data['name'] == 'compression_format',
            );

            if (!hasCompressionFormatColumn) {
              await m.addColumn(
                schedulesTable,
                schedulesTable.compressionFormat,
              );

              await customStatement(
                "UPDATE schedules_table SET compression_format = CASE "
                "WHEN compress_backup = 0 THEN 'none' "
                "ELSE 'zip' END",
              );

              LoggerService.info(
                'Coluna compression_format adicionada à tabela schedules_table',
              );
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro ao verificar/adicionar coluna compression_format',
              e,
              stackTrace,
            );
          }
        }

        if (from < 13) {
          // Migração para versão 13: criar tabela licenses_table
          try {
            final tables = await (customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='licenses_table'",
            ).get());
            final hasTable = tables.isNotEmpty;

            if (!hasTable) {
              await m.createTable(licensesTable);
              LoggerService.info(
                'Migração v13: Tabela licenses_table criada com sucesso',
              );
            }
          } catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v13 para licenses_table',
              e,
              stackTrace,
            );
          }
        }
      },
      beforeOpen: (details) async {
        // Verificar e criar tabela sybase_configs se não existir
        // Isso garante que a tabela existe mesmo para bancos antigos que nunca migraram
        await _ensureSybaseConfigsTableExistsDirect();

        // Migrar colunas de camelCase para snake_case se necessário
        await _migrateSybaseColumnsToSnakeCase();

        // Garantir que as colunas de email_configs existem
        await _ensureEmailConfigsColumnsExist();
      },
    );
  }

  Future<void> _ensureSybaseConfigsTableExists(Migrator m) async {
    try {
      final tableExists = await (customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sybase_configs'",
      ).getSingleOrNull());

      if (tableExists == null) {
        LoggerService.info('Criando tabela sybase_configs...');
        await m.createTable(sybaseConfigsTable);
        LoggerService.info('Tabela sybase_configs criada com sucesso');
      }
    } catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao verificar/criar tabela sybase_configs',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _ensureSybaseConfigsTableExistsDirect() async {
    try {
      final tableExists = await (customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sybase_configs'",
      ).getSingleOrNull());

      if (tableExists == null) {
        LoggerService.info(
          'Tabela sybase_configs não existe, criando via SQL...',
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
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao criar tabela sybase_configs', e, stackTrace);
    }
  }

  Future<void> _migrateSybaseColumnsToSnakeCase() async {
    try {
      final columns = await (customSelect(
        "PRAGMA table_info(sybase_configs)",
      ).get());

      final columnNames = columns
          .map((row) => row.data['name'] as String)
          .toSet();

      // Verificar se a tabela usa nomes em camelCase (antigo)
      final hasCamelCaseColumns =
          columnNames.contains('serverName') ||
          columnNames.contains('databaseName') ||
          columnNames.contains('createdAt');

      // Verificar se já está em snake_case (novo)
      final hasSnakeCaseColumns =
          columnNames.contains('server_name') ||
          columnNames.contains('database_name') ||
          columnNames.contains('created_at');

      if (hasCamelCaseColumns && !hasSnakeCaseColumns) {
        LoggerService.info(
          'Migrando colunas sybase_configs de camelCase para snake_case...',
        );

        // Criar nova tabela com nomes corretos
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

        // Copiar dados da tabela antiga para a nova
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

        // Remover tabela antiga e renomear nova
        await customStatement('DROP TABLE sybase_configs');
        await customStatement(
          'ALTER TABLE sybase_configs_new RENAME TO sybase_configs',
        );

        LoggerService.info(
          'Migração de colunas sybase_configs concluída com sucesso',
        );
      }
    } catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao migrar colunas sybase_configs para snake_case',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _ensureEmailConfigsColumnsExist() async {
    try {
      final tableExists = await (customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='email_configs_table'",
      ).getSingleOrNull());

      if (tableExists == null) {
        // Tabela não existe, será criada pelo onCreate
        return;
      }

      final columns = await (customSelect(
        "PRAGMA table_info(email_configs_table)",
      ).get());
      final columnNames = columns
          .map((row) => row.data['name'] as String)
          .toSet();

      // Lista de colunas esperadas na tabela
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

      // Identificar colunas obsoletas (existem no banco mas não estão na definição)
      final obsoleteColumns = columnNames
          .where((col) => !expectedColumns.contains(col))
          .toList();

      if (obsoleteColumns.isNotEmpty) {
        LoggerService.info(
          'Colunas obsoletas encontradas em email_configs_table: ${obsoleteColumns.join(", ")}',
        );
        // Nota: SQLite não suporta DROP COLUMN diretamente, então apenas logamos
        // Para remover colunas, seria necessário recriar a tabela
      }

      if (!columnNames.contains('from_email')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN from_email TEXT",
        );
        LoggerService.info(
          'Coluna from_email adicionada à email_configs_table',
        );
      }
      if (!columnNames.contains('from_name')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN from_name TEXT",
        );
        LoggerService.info('Coluna from_name adicionada à email_configs_table');
      }
      if (!columnNames.contains('smtp_server')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN smtp_server TEXT",
        );
        LoggerService.info(
          'Coluna smtp_server adicionada à email_configs_table',
        );
      }
      if (!columnNames.contains('smtp_port')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN smtp_port INTEGER",
        );
        LoggerService.info('Coluna smtp_port adicionada à email_configs_table');
      }
      if (!columnNames.contains('username')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN username TEXT",
        );
        LoggerService.info('Coluna username adicionada à email_configs_table');
      }
      if (!columnNames.contains('password')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN password TEXT",
        );
        LoggerService.info('Coluna password adicionada à email_configs_table');
      }
      if (!columnNames.contains('use_ssl')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN use_ssl INTEGER",
        );
        LoggerService.info('Coluna use_ssl adicionada à email_configs_table');
      }

      // Sempre atualizar valores null para valores padrão (não apenas quando colunas são adicionadas)
      try {
        final tableName = 'email_configs_table';
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
          'Valores padrão atualizados para registros existentes em email_configs_table',
        );
      } catch (e, stackTrace) {
        LoggerService.warning(
          'Erro ao atualizar valores padrão em email_configs_table',
          e,
          stackTrace,
        );
      }
    } catch (e, stackTrace) {
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
