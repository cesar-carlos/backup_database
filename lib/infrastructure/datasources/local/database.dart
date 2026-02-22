import 'dart:convert';
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
    ScheduleDestinationsTable,
    SchedulesTable,
    BackupHistoryTable,
    BackupLogsTable,
    EmailConfigsTable,
    EmailNotificationTargetsTable,
    EmailTestAuditTable,
    LicensesTable,
    ServerCredentialsTable,
    ConnectionLogsTable,
    ServerConnectionsTable,
    FileTransfersTable,
  ],
  daos: [
    SqlServerConfigDao,
    SybaseConfigDao,
    PostgresConfigDao,
    BackupDestinationDao,
    ScheduleDestinationDao,
    ScheduleDao,
    BackupHistoryDao,
    BackupLogDao,
    EmailConfigDao,
    EmailNotificationTargetDao,
    EmailTestAuditDao,
    LicenseDao,
    ServerCredentialDao,
    ConnectionLogDao,
    ServerConnectionDao,
    FileTransferDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({String databaseName = 'backup_database'})
    : super(_openConnection(databaseName));

  AppDatabase.inMemory()
    : super(LazyDatabase(() async => NativeDatabase.memory()));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 24;

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

        if (from < 14) {
          try {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS server_credentials_table (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                name TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL,
                last_used_at INTEGER,
                description TEXT
              )
            ''');
            LoggerService.info(
              'Migração v14: Tabela server_credentials_table criada.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v14 para server_credentials_table',
              e,
              stackTrace,
            );
          }

          try {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS connection_logs_table (
                id TEXT PRIMARY KEY NOT NULL,
                client_host TEXT NOT NULL,
                server_id TEXT,
                success INTEGER NOT NULL,
                error_message TEXT,
                timestamp INTEGER NOT NULL,
                client_id TEXT
              )
            ''');
            LoggerService.info(
              'Migração v14: Tabela connection_logs_table criada.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v14 para connection_logs_table',
              e,
              stackTrace,
            );
          }

          try {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS server_connections_table (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                server_id TEXT NOT NULL,
                host TEXT NOT NULL,
                port INTEGER NOT NULL DEFAULT 9527,
                password TEXT NOT NULL,
                is_online INTEGER NOT NULL DEFAULT 0,
                last_connected_at INTEGER,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
              )
            ''');
            LoggerService.info(
              'Migração v14: Tabela server_connections_table criada.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v14 para server_connections_table',
              e,
              stackTrace,
            );
          }

          try {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS file_transfers_table (
                id TEXT PRIMARY KEY NOT NULL,
                schedule_id TEXT NOT NULL,
                file_name TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                current_chunk INTEGER NOT NULL DEFAULT 0,
                total_chunks INTEGER NOT NULL,
                status TEXT NOT NULL,
                error_message TEXT,
                started_at INTEGER,
                completed_at INTEGER,
                source_path TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                checksum TEXT NOT NULL
              )
            ''');
            LoggerService.info(
              'Migração v14: Tabela file_transfers_table criada.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v14 para file_transfers_table',
              e,
              stackTrace,
            );
          }

          try {
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_server_credentials_active
              ON server_credentials_table(is_active)
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_connection_logs_timestamp
              ON connection_logs_table(timestamp DESC)
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_file_transfers_schedule
              ON file_transfers_table(schedule_id)
            ''');
            LoggerService.info(
              'Migração v14: Índices criados.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v14 ao criar índices',
              e,
              stackTrace,
            );
          }
        }

        if (from < 15) {
          try {
            final columns = await customSelect(
              'PRAGMA table_info(backup_destinations_table)',
            ).get();
            final hasTempPathColumn = columns.any(
              (row) => row.data['name'] == 'temp_path',
            );

            if (!hasTempPathColumn) {
              await customStatement(
                'ALTER TABLE backup_destinations_table '
                'ADD COLUMN temp_path TEXT',
              );
              LoggerService.info(
                'Migração v15: Coluna temp_path adicionada à '
                'backup_destinations_table.',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v15 para backup_destinations_table (temp_path)',
              e,
              stackTrace,
            );
          }
        }

        if (from < 16) {
          try {
            final columns = await customSelect(
              'PRAGMA table_info(backup_destinations_table)',
            ).get();
            final hasTempPathColumn = columns.any(
              (row) => row.data['name'] == 'temp_path',
            );

            if (hasTempPathColumn) {
              await customStatement(
                'ALTER TABLE backup_destinations_table '
                'DROP COLUMN temp_path',
              );
              LoggerService.info(
                'Migração v16: Coluna temp_path removida de '
                'backup_destinations_table. Agora usando TempDirectoryService.',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v16 para backup_destinations_table (remover temp_path)',
              e,
              stackTrace,
            );
          }
        }

        if (from < 17) {
          try {
            await m.createTable(scheduleDestinationsTable);
            await _createScheduleDestinationIndexes();
            await _backfillScheduleDestinations();
            LoggerService.info(
              'Migração v17: Tabela schedule_destinations_table criada com '
              'backfill concluído.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v17 para schedule_destinations_table',
              e,
              stackTrace,
            );
          }
        }

        if (from < 18) {
          try {
            await _createScheduleDatabaseConfigIntegrityTriggers();
            LoggerService.info(
              'Migracao v18: Triggers de integridade para configuracao de '
              'banco em schedules_table criados.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migracao v18 de integridade schedule/configuracao',
              e,
              stackTrace,
            );
          }
        }

        if (from < 19) {
          try {
            await _ensureEmailNotificationTargetsSchema();
            await _backfillEmailNotificationTargetsFromLegacy();
            LoggerService.info(
              'Migracao v19: schema de notificacoes multi-destinatario '
              'criado e dados legados migrados.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migracao v19 de notificacoes multi-destinatario',
              e,
              stackTrace,
            );
          }
        }

        if (from < 20) {
          try {
            await _cleanupLegacyEmailNotificationFields();
            LoggerService.info(
              'Migracao v20: limpeza de campos legados de notificacao '
              'concluida.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migracao v20 de limpeza de campos legados de '
              'notificacao',
              e,
              stackTrace,
            );
          }
        }

        if (from < 21) {
          try {
            await _ensureEmailTestAuditSchema();
            LoggerService.info(
              'Migracao v21: tabela de auditoria de teste SMTP criada.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migracao v21 de auditoria de teste SMTP',
              e,
              stackTrace,
            );
          }
        }

        if (from < 22) {
          try {
            await _ensureEmailConfigSmtpPasswordKeyColumn();
            LoggerService.info(
              'Migracao v22: coluna smtp_password_key garantida '
              'em email_configs_table.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migracao v22 de smtp_password_key',
              e,
              stackTrace,
            );
          }
        }

        if (from < 23) {
          try {
            await _ensureEmailConfigOAuthColumns();
            LoggerService.info(
              'Migracao v23: colunas OAuth SMTP garantidas '
              'em email_configs_table.',
            );
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migracao v23 de OAuth SMTP',
              e,
              stackTrace,
            );
          }
        }

        if (from < 24) {
          try {
            final schedulesColumns = await customSelect(
              'PRAGMA table_info(schedules_table)',
            ).get();
            final columnNames = schedulesColumns
                .map((row) => row.data['name'] as String)
                .toSet();

            if (!columnNames.contains('backup_timeout_seconds')) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN backup_timeout_seconds '
                'INTEGER NOT NULL DEFAULT 7200',
              );
              LoggerService.info(
                'Migração v24: Coluna backup_timeout_seconds adicionada à '
                'schedules_table',
              );
            }

            if (!columnNames.contains('verify_timeout_seconds')) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN verify_timeout_seconds '
                'INTEGER NOT NULL DEFAULT 1800',
              );
              LoggerService.info(
                'Migração v24: Coluna verify_timeout_seconds adicionada à '
                'schedules_table',
              );
            }

            if (!columnNames.contains('created_at')) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN created_at '
                'INTEGER NOT NULL DEFAULT 0',
              );
              await customStatement(
                'UPDATE schedules_table SET created_at = '
                "strftime('%s', 'now') * 1000000 WHERE created_at = 0",
              );
              LoggerService.info(
                'Migração v24: Coluna created_at adicionada à schedules_table',
              );
            }

            if (!columnNames.contains('updated_at')) {
              await customStatement(
                'ALTER TABLE schedules_table ADD COLUMN updated_at '
                'INTEGER NOT NULL DEFAULT 0',
              );
              await customStatement(
                'UPDATE schedules_table SET updated_at = '
                "strftime('%s', 'now') * 1000000 WHERE updated_at = 0",
              );
              LoggerService.info(
                'Migração v24: Coluna updated_at adicionada à schedules_table',
              );
            }
          } on Object catch (e, stackTrace) {
            LoggerService.warning(
              'Erro na migração v24 para timeout e timestamp columns',
              e,
              stackTrace,
            );
          }
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');

        // P1.1: Verifica e recria tabelas de configuração via schema Drift
        // Se as tabelas foram dropadas (pelo reset v2.2.3), reseta
        // a versão do schema para forçar Drift a recriá-las via onCreate.
        await _ensureConfigTablesRecreatedByDrift();

        await _ensureScheduleDestinationsTableExists();
        await _createScheduleDestinationIndexes();
        await _createScheduleDatabaseConfigIntegrityTriggers();

        await _migrateSybaseColumnsToSnakeCase();

        await _ensureTimestampColumnsForAllTables();

        await _ensureEmailConfigsColumnsExist();
        await _ensureEmailConfigSmtpPasswordKeyColumn();
        await _ensureEmailConfigOAuthColumns();
        await _ensureEmailNotificationTargetsSchema();
        await _ensureEmailTestAuditSchema();
        await _ensureSchedulesTimeoutAndTimestampColumns();
      },
    );
  }

  Future<void> _ensureEmailConfigSmtpPasswordKeyColumn() async {
    try {
      final columns = await customSelect(
        'PRAGMA table_info(email_configs_table)',
      ).get();
      final hasColumn = columns.any(
        (row) => row.data['name'] == 'smtp_password_key',
      );

      if (!hasColumn) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN smtp_password_key TEXT NOT NULL DEFAULT ''",
        );
      }

      await customStatement(
        '''
        UPDATE email_configs_table
        SET smtp_password_key = 'email_smtp_password_' || id
        WHERE smtp_password_key IS NULL OR smtp_password_key = ''
        ''',
      );
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao garantir coluna smtp_password_key em email_configs_table',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _ensureEmailConfigOAuthColumns() async {
    try {
      final columns = await customSelect(
        'PRAGMA table_info(email_configs_table)',
      ).get();
      final columnNames = columns
          .map((row) => row.data['name'] as String)
          .toSet();

      if (!columnNames.contains('auth_mode')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN auth_mode TEXT NOT NULL DEFAULT 'password'",
        );
      }
      if (!columnNames.contains('oauth_provider')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN oauth_provider TEXT',
        );
      }
      if (!columnNames.contains('oauth_account_email')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN oauth_account_email TEXT',
        );
      }
      if (!columnNames.contains('oauth_token_key')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN oauth_token_key TEXT',
        );
      }
      if (!columnNames.contains('oauth_connected_at')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN oauth_connected_at INTEGER',
        );
      }

      await customStatement(
        '''
        UPDATE email_configs_table
        SET auth_mode = COALESCE(NULLIF(auth_mode, ''), 'password')
        ''',
      );
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao garantir colunas OAuth SMTP em email_configs_table',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _ensureEmailTestAuditSchema() async {
    try {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS email_test_audit_table (
          id TEXT PRIMARY KEY NOT NULL,
          config_id TEXT NOT NULL,
          correlation_id TEXT NOT NULL,
          recipient_email TEXT NOT NULL,
          sender_email TEXT NOT NULL,
          smtp_server TEXT NOT NULL,
          smtp_port INTEGER NOT NULL,
          status TEXT NOT NULL,
          error_type TEXT,
          error_message TEXT,
          attempts INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL
        )
      ''');

      await customStatement('''
        CREATE INDEX IF NOT EXISTS idx_email_test_audit_config_created_at
        ON email_test_audit_table(config_id, created_at DESC)
      ''');

      await customStatement('''
        CREATE INDEX IF NOT EXISTS idx_email_test_audit_created_at
        ON email_test_audit_table(created_at DESC)
      ''');
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao garantir schema de auditoria SMTP',
        e,
        stackTrace,
      );
    }
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

  /// P1.1: Verifica e recria tabelas de configuração via schema Drift.
  ///
  /// Se as tabelas foram dropadas (pelo reset v2.2.3), reseta
  /// a versão do schema para forçar Drift a recriá-las via onCreate.
  Future<void> _ensureConfigTablesRecreatedByDrift() async {
    try {
      final tables = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name IN ('sql_server_configs_table', 'sybase_configs_table', "
        "'postgres_configs_table', 'schedules_table')",
      ).get();
      final existingTableNames = tables
          .map((row) => row.data['name'] as String)
          .toSet();

      final missingTables = [
        'sql_server_configs_table',
        'sybase_configs_table',
        'postgres_configs_table',
        'schedules_table',
      ].where((table) => !existingTableNames.contains(table)).toList();

      if (missingTables.isNotEmpty) {
        final missingTablesStr = missingTables.join(', ');
        LoggerService.warning(
          'Tabelas de configuração ausentes: $missingTablesStr',
        );
        LoggerService.info(
          'Resetando versão do schema para forçar recriação via Drift',
        );

        await customStatement('PRAGMA user_version = 0');
        LoggerService.info('Versão do schema resetada para 0');
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao verificar/recriar tabelas de configuração',
        e,
        stackTrace,
      );
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
        'config_name',
        'sender_name',
        'from_email',
        'from_name',
        'smtp_server',
        'smtp_port',
        'username',
        'password',
        'smtp_password_key',
        'auth_mode',
        'oauth_provider',
        'oauth_account_email',
        'oauth_token_key',
        'oauth_connected_at',
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
      if (!columnNames.contains('smtp_password_key')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN smtp_password_key TEXT NOT NULL DEFAULT ''",
        );
        LoggerService.info(
          'Coluna smtp_password_key adicionada à email_configs_table',
        );
      }
      if (!columnNames.contains('use_ssl')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN use_ssl INTEGER',
        );
        LoggerService.info('Coluna use_ssl adicionada à email_configs_table');
      }
      if (!columnNames.contains('auth_mode')) {
        await customStatement(
          "ALTER TABLE email_configs_table ADD COLUMN auth_mode TEXT NOT NULL DEFAULT 'password'",
        );
        LoggerService.info('Coluna auth_mode adicionada à email_configs_table');
      }
      if (!columnNames.contains('oauth_provider')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN oauth_provider TEXT',
        );
        LoggerService.info(
          'Coluna oauth_provider adicionada à email_configs_table',
        );
      }
      if (!columnNames.contains('oauth_account_email')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN oauth_account_email TEXT',
        );
        LoggerService.info(
          'Coluna oauth_account_email adicionada à email_configs_table',
        );
      }
      if (!columnNames.contains('oauth_token_key')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN oauth_token_key TEXT',
        );
        LoggerService.info(
          'Coluna oauth_token_key adicionada à email_configs_table',
        );
      }
      if (!columnNames.contains('oauth_connected_at')) {
        await customStatement(
          'ALTER TABLE email_configs_table ADD COLUMN oauth_connected_at INTEGER',
        );
        LoggerService.info(
          'Coluna oauth_connected_at adicionada à email_configs_table',
        );
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
            smtp_password_key = COALESCE(smtp_password_key, ''),
            auth_mode = COALESCE(NULLIF(auth_mode, ''), 'password'),
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
            OR smtp_password_key IS NULL
            OR auth_mode IS NULL
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

  Future<void> _ensureEmailNotificationTargetsSchema() async {
    try {
      final columns = await customSelect(
        'PRAGMA table_info(email_configs_table)',
      ).get();
      final hasConfigNameColumn = columns.any(
        (row) => row.data['name'] == 'config_name',
      );

      if (!hasConfigNameColumn) {
        await customStatement(
          '''ALTER TABLE email_configs_table ADD COLUMN config_name TEXT NOT NULL DEFAULT 'Configuracao SMTP' ''',
        );
        LoggerService.info(
          'Coluna config_name adicionada em email_configs_table.',
        );
      }

      await customStatement('''
        CREATE TABLE IF NOT EXISTS email_notification_targets_table (
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

      await customStatement('''
        CREATE INDEX IF NOT EXISTS idx_email_notification_targets_config_id
        ON email_notification_targets_table(email_config_id)
      ''');
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao garantir schema de email_notification_targets',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _backfillEmailNotificationTargetsFromLegacy() async {
    try {
      final rows = await customSelect('''
        SELECT 
          id,
          recipients,
          notify_on_success,
          notify_on_error,
          notify_on_warning
        FROM email_configs_table
      ''').get();

      for (final row in rows) {
        final configId = row.read<String>('id');
        final recipientsRaw = row.read<String>('recipients');
        final notifyOnSuccess = row.read<int>('notify_on_success');
        final notifyOnError = row.read<int>('notify_on_error');
        final notifyOnWarning = row.read<int>('notify_on_warning');

        List<String> recipients;
        try {
          recipients = (jsonDecode(recipientsRaw) as List<dynamic>)
              .whereType<String>()
              .map((r) => r.trim())
              .where((r) => r.isNotEmpty)
              .toSet()
              .toList();
        } on Object catch (e) {
          LoggerService.warning(
            'Falha ao parsear recipients da configuracao $configId: $e',
          );
          recipients = const [];
        }

        for (final recipient in recipients) {
          final targetId = '$configId:$recipient';
          final now = DateTime.now().millisecondsSinceEpoch;
          await customStatement(
            '''
            INSERT OR IGNORE INTO email_notification_targets_table (
              id,
              email_config_id,
              recipient_email,
              notify_on_success,
              notify_on_error,
              notify_on_warning,
              enabled,
              created_at,
              updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
            ''',
            [
              targetId,
              configId,
              recipient,
              notifyOnSuccess,
              notifyOnError,
              notifyOnWarning,
              now,
              now,
            ],
          );
        }
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro no backfill de email_notification_targets_table',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _cleanupLegacyEmailNotificationFields() async {
    try {
      await customStatement(
        '''
        UPDATE email_configs_table
        SET
          recipients = '[]',
          notify_on_success = 1,
          notify_on_error = 1,
          notify_on_warning = 1,
          updated_at = ?
        WHERE
          recipients != '[]'
          OR notify_on_success != 1
          OR notify_on_error != 1
          OR notify_on_warning != 1
        ''',
        [DateTime.now().millisecondsSinceEpoch],
      );
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao limpar campos legados de notificacao',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _ensureScheduleDestinationsTableExists() async {
    try {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS schedule_destinations_table (
          id TEXT PRIMARY KEY NOT NULL,
          schedule_id TEXT NOT NULL,
          destination_id TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          UNIQUE(schedule_id, destination_id),
          FOREIGN KEY(schedule_id) REFERENCES schedules_table(id)
            ON DELETE CASCADE,
          FOREIGN KEY(destination_id) REFERENCES backup_destinations_table(id)
            ON DELETE RESTRICT
        )
      ''');
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao garantir tabela schedule_destinations_table',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _createScheduleDestinationIndexes() async {
    try {
      await customStatement('''
        CREATE INDEX IF NOT EXISTS idx_schedule_destinations_schedule_id
        ON schedule_destinations_table(schedule_id)
      ''');
      await customStatement('''
        CREATE INDEX IF NOT EXISTS idx_schedule_destinations_destination_id
        ON schedule_destinations_table(destination_id)
      ''');
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao criar índices de schedule_destinations_table',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _backfillScheduleDestinations() async {
    try {
      final existingDestinations = await customSelect(
        'SELECT id FROM backup_destinations_table',
      ).get();
      final destinationIds = existingDestinations
          .map((row) => row.read<String>('id'))
          .toSet();

      if (destinationIds.isEmpty) {
        return;
      }

      final schedules = await customSelect(
        'SELECT id, destination_ids FROM schedules_table',
      ).get();

      for (final row in schedules) {
        final scheduleId = row.read<String>('id');
        final destinationIdsRaw = row.read<String>('destination_ids');
        List<String> ids;

        try {
          ids = (jsonDecode(destinationIdsRaw) as List).cast<String>();
        } on Object catch (e) {
          LoggerService.warning(
            'Não foi possível converter destination_ids do schedule '
            '$scheduleId durante backfill: $e',
          );
          continue;
        }

        for (final destinationId in ids.toSet()) {
          if (!destinationIds.contains(destinationId)) {
            LoggerService.warning(
              'Destino $destinationId referenciado por schedule $scheduleId '
              'não existe. Ignorando vínculo no backfill.',
            );
            continue;
          }

          await customStatement(
            '''
            INSERT OR IGNORE INTO schedule_destinations_table
              (id, schedule_id, destination_id, created_at)
            VALUES (?, ?, ?, ?)
            ''',
            [
              '$scheduleId:$destinationId',
              scheduleId,
              destinationId,
              DateTime.now().millisecondsSinceEpoch,
            ],
          );
        }
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro no backfill de schedule_destinations_table',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _createScheduleDatabaseConfigIntegrityTriggers() async {
    try {
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_schedules_validate_config_insert
        BEFORE INSERT ON schedules_table
        BEGIN
          SELECT RAISE(ABORT, 'database_type invalido em schedules_table')
          WHERE NEW.database_type NOT IN ('sqlServer', 'sybase', 'postgresql');

          SELECT RAISE(ABORT, 'Configuracao SQL Server inexistente para agendamento')
          WHERE NEW.database_type = 'sqlServer' AND NOT EXISTS (
            SELECT 1 FROM sql_server_configs_table c
            WHERE c.id = NEW.database_config_id
          );

          SELECT RAISE(ABORT, 'Configuracao Sybase inexistente para agendamento')
          WHERE NEW.database_type = 'sybase' AND NOT EXISTS (
            SELECT 1 FROM sybase_configs c
            WHERE c.id = NEW.database_config_id
          );

          SELECT RAISE(ABORT, 'Configuracao PostgreSQL inexistente para agendamento')
          WHERE NEW.database_type = 'postgresql' AND NOT EXISTS (
            SELECT 1 FROM postgres_configs_table c
            WHERE c.id = NEW.database_config_id
          );
        END;
      ''');

      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_schedules_validate_config_update
        BEFORE UPDATE OF database_type, database_config_id ON schedules_table
        BEGIN
          SELECT RAISE(ABORT, 'database_type invalido em schedules_table')
          WHERE NEW.database_type NOT IN ('sqlServer', 'sybase', 'postgresql');

          SELECT RAISE(ABORT, 'Configuracao SQL Server inexistente para agendamento')
          WHERE NEW.database_type = 'sqlServer' AND NOT EXISTS (
            SELECT 1 FROM sql_server_configs_table c
            WHERE c.id = NEW.database_config_id
          );

          SELECT RAISE(ABORT, 'Configuracao Sybase inexistente para agendamento')
          WHERE NEW.database_type = 'sybase' AND NOT EXISTS (
            SELECT 1 FROM sybase_configs c
            WHERE c.id = NEW.database_config_id
          );

          SELECT RAISE(ABORT, 'Configuracao PostgreSQL inexistente para agendamento')
          WHERE NEW.database_type = 'postgresql' AND NOT EXISTS (
            SELECT 1 FROM postgres_configs_table c
            WHERE c.id = NEW.database_config_id
          );
        END;
      ''');

      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_sql_server_configs_restrict_delete
        BEFORE DELETE ON sql_server_configs_table
        BEGIN
          SELECT RAISE(ABORT, 'Configuracao em uso por agendamentos')
          WHERE EXISTS (
            SELECT 1 FROM schedules_table s
            WHERE s.database_type = 'sqlServer'
              AND s.database_config_id = OLD.id
          );
        END;
      ''');

      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_sybase_configs_restrict_delete
        BEFORE DELETE ON sybase_configs
        BEGIN
          SELECT RAISE(ABORT, 'Configuracao em uso por agendamentos')
          WHERE EXISTS (
            SELECT 1 FROM schedules_table s
            WHERE s.database_type = 'sybase'
              AND s.database_config_id = OLD.id
          );
        END;
      ''');

      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS trg_postgres_configs_restrict_delete
        BEFORE DELETE ON postgres_configs_table
        BEGIN
          SELECT RAISE(ABORT, 'Configuracao em uso por agendamentos')
          WHERE EXISTS (
            SELECT 1 FROM schedules_table s
            WHERE s.database_type = 'postgresql'
              AND s.database_config_id = OLD.id
          );
        END;
      ''');
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao criar triggers de integridade schedule/configuracao',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _ensureSchedulesTimeoutAndTimestampColumns() async {
    try {
      final schedulesColumns = await customSelect(
        'PRAGMA table_info(schedules_table)',
      ).get();
      final columnNames = schedulesColumns
          .map((row) => row.data['name'] as String)
          .toSet();

      if (!columnNames.contains('backup_timeout_seconds')) {
        await customStatement(
          'ALTER TABLE schedules_table ADD COLUMN backup_timeout_seconds '
          'INTEGER NOT NULL DEFAULT 7200',
        );
        LoggerService.info(
          'Coluna backup_timeout_seconds adicionada à schedules_table',
        );
      }

      if (!columnNames.contains('verify_timeout_seconds')) {
        await customStatement(
          'ALTER TABLE schedules_table ADD COLUMN verify_timeout_seconds '
          'INTEGER NOT NULL DEFAULT 1800',
        );
        LoggerService.info(
          'Coluna verify_timeout_seconds adicionada à schedules_table',
        );
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao garantir colunas de timeout em schedules_table',
        e,
        stackTrace,
      );
    }
  }

  /// Ensures created_at and updated_at columns exist in all tables that
  /// require them. This covers all tables where these columns were added after
  /// initial schema creation, preventing null-check errors on existing databases.
  Future<void> _ensureTimestampColumnsForAllTables() async {
    const tablesWithBoth = [
      'sql_server_configs_table',
      'sybase_configs_table',
      'postgres_configs_table',
      'licenses_table',
      'backup_destinations_table',
      'server_connections_table',
      'email_configs_table',
      'schedules_table',
    ];

    const tablesWithCreatedAtOnly = [
      'server_credentials_table',
      'backup_logs_table',
    ];

    for (final table in tablesWithBoth) {
      await _ensureTableTimestampColumns(table, addUpdatedAt: true);
    }
    for (final table in tablesWithCreatedAtOnly) {
      await _ensureTableTimestampColumns(table, addUpdatedAt: false);
    }
  }

  Future<void> _ensureTableTimestampColumns(
    String tableName, {
    required bool addUpdatedAt,
  }) async {
    try {
      final tableExists = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$tableName'",
      ).getSingleOrNull();

      if (tableExists == null) return;

      final columns = await customSelect(
        'PRAGMA table_info($tableName)',
      ).get();
      final columnNames = columns
          .map((row) => row.data['name'] as String)
          .toSet();

      if (!columnNames.contains('created_at')) {
        await customStatement(
          'ALTER TABLE $tableName ADD COLUMN created_at '
          'INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'UPDATE $tableName SET created_at = '
          "CAST(strftime('%s', 'now') AS INTEGER) * 1000000 "
          'WHERE created_at = 0',
        );
        LoggerService.info('Coluna created_at adicionada à $tableName');
      }

      if (addUpdatedAt && !columnNames.contains('updated_at')) {
        await customStatement(
          'ALTER TABLE $tableName ADD COLUMN updated_at '
          'INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'UPDATE $tableName SET updated_at = '
          "CAST(strftime('%s', 'now') AS INTEGER) * 1000000 "
          'WHERE updated_at = 0',
        );
        LoggerService.info('Coluna updated_at adicionada à $tableName');
      }
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Erro ao garantir colunas de timestamp em $tableName',
        e,
        stackTrace,
      );
    }
  }
}

LazyDatabase _openConnection([String databaseName = 'backup_database']) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, '$databaseName.db'));
    return NativeDatabase.createInBackground(file);
  });
}
