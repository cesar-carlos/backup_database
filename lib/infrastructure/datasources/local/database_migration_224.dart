import 'dart:io';

import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _resetFlagKey = 'reset_v2_2_4_done';

Future<Map<String, dynamic>?> runFullDatabaseMigration224() async {
  const storage = FlutterSecureStorage();
  try {
    final flag = await storage.read(key: _resetFlagKey);
    if (flag == 'true') {
      return null;
    }
  } on Exception catch (e) {
    LoggerService.warning('Erro ao ler flag de migração 2.2.4: $e');
    return null;
  }

  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version;
  final targetVersion = Version.parse('2.2.4');

  Version? currentVersion;
  try {
    currentVersion = Version.parse(version.split('+').first);
  } on Exception catch (e) {
    LoggerService.warning('Versão inválida: $version');
    return null;
  }

  if (currentVersion != targetVersion) {
    LoggerService.info(
      'Versão $version não é 2.2.4, pulando migração completa',
    );
    return null;
  }

  final appDataDir = await getApplicationDocumentsDirectory();
  final databaseName = getDatabaseNameForMode(currentAppMode);
  final dbPath = p.join(appDataDir.path, '$databaseName.db');
  final dbFile = File(dbPath);

  if (!await dbFile.exists()) {
    LoggerService.info('Banco não existe, migração 2.2.4 desnecessária');
    return null;
  }

  final fileSize = await dbFile.length();
  if (fileSize == 0) {
    LoggerService.info('Banco vazio, deletando e recriando');
    await dbFile.delete();
    await _markMigration224Done();
    return null;
  }

  LoggerService.info('===== MIGRAÇÃO COMPLETA 2.2.4 =====');
  LoggerService.info('Exportando dados de $dbPath...');

  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbPath);
    final exportData = _exportAllData(db);
    db.dispose();
    db = null;

    final backupPath =
        '${dbPath}_backup_v2_2_4_${DateTime.now().millisecondsSinceEpoch}';
    LoggerService.info('Criando backup em $backupPath');
    await dbFile.copy(backupPath);

    LoggerService.info('Removendo banco antigo...');
    await dbFile.delete();

    await _markMigration224Done();
    LoggerService.info(
      'Migração 2.2.4: export concluído, import será feito após criação do banco',
    );
    return exportData;
  } on Object catch (e, stackTrace) {
    LoggerService.error('Erro na migração 2.2.4', e, stackTrace);
    db?.dispose();
    return null;
  }
}

Future<void> _markMigration224Done() async {
  const storage = FlutterSecureStorage();
  try {
    await storage.write(key: _resetFlagKey, value: 'true');
    LoggerService.info('Flag de migração 2.2.4 marcada como concluída');
  } on Exception catch (e) {
    LoggerService.warning('Erro ao gravar flag de migração: $e');
  }
}

Map<String, dynamic> _exportAllData(sqlite3.Database db) {
  final data = <String, dynamic>{};

  void exportTable(String table, String key) {
    try {
      final result = db.select('SELECT * FROM $table');
      data[key] = result.map(Map<String, dynamic>.from).toList();
    } on Object catch (e) {
      LoggerService.warning('Export $table: $e');
      data[key] = <Map<String, dynamic>>[];
    }
  }

  exportTable('sql_server_configs_table', 'sql_server_configs');
  exportTable('sybase_configs_table', 'sybase_configs');
  exportTable('postgres_configs_table', 'postgres_configs');
  exportTable('backup_destinations_table', 'destinations');
  exportTable('schedules_table', 'schedules');
  exportTable('schedule_destinations_table', 'schedule_destinations');
  exportTable('backup_history_table', 'backup_history');
  exportTable('backup_logs_table', 'backup_logs');
  exportTable('email_configs_table', 'email_configs');
  exportTable('email_notification_targets_table', 'email_notification_targets');
  exportTable('licenses_table', 'licenses');

  return data;
}

Future<void> importMigration224Data(
  AppDatabase database,
  Map<String, dynamic> data,
) async {
  LoggerService.info('Importando dados da migração 2.2.4...');

  await database.customStatement('PRAGMA foreign_keys = OFF');

  try {
    await _importSqlServerConfigs(
      database,
      data['sql_server_configs'] as List<dynamic>,
    );
    await _importSybaseConfigs(
      database,
      data['sybase_configs'] as List<dynamic>,
    );
    await _importPostgresConfigs(
      database,
      data['postgres_configs'] as List<dynamic>,
    );
    await _importDestinations(database, data['destinations'] as List<dynamic>);
    await _importEmailConfigs(database, data['email_configs'] as List<dynamic>);
    await _importEmailTargets(
      database,
      data['email_notification_targets'] as List<dynamic>,
    );
    await _importLicenses(database, data['licenses'] as List<dynamic>);
    await _importSchedules(database, data['schedules'] as List<dynamic>);
    await _importScheduleDestinations(
      database,
      data['schedule_destinations'] as List<dynamic>,
    );
    await _importBackupHistory(
      database,
      data['backup_history'] as List<dynamic>,
    );
    await _importBackupLogs(database, data['backup_logs'] as List<dynamic>);
  } finally {
    await database.customStatement('PRAGMA foreign_keys = ON');
  }

  LoggerService.info('Importação 2.2.4 concluída');
}

Future<void> _importSqlServerConfigs(
  AppDatabase db,
  List<dynamic> configs,
) async {
  for (final c in configs) {
    final config = c as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO sql_server_configs_table (
          id, name, server, database, username, password, port,
          enabled, use_windows_auth, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          config['id'],
          config['name'],
          config['server'],
          config['database'],
          config['username'],
          config['password'] ?? '',
          config['port'] ?? 1433,
          config['enabled'] ?? 1,
          config['use_windows_auth'] ?? 0,
          config['created_at'],
          config['updated_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import SQL Server config ${config['id']}: $e');
    }
  }
}

Future<void> _importSybaseConfigs(
  AppDatabase db,
  List<dynamic> configs,
) async {
  for (final c in configs) {
    final config = c as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO sybase_configs_table (
          id, name, server_name, database_name, database_file, username,
          password, port, enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          config['id'],
          config['name'],
          config['server_name'] ?? config['serverName'],
          config['database_name'] ?? config['databaseName'] ?? '',
          config['database_file'] ?? config['databaseFile'] ?? '',
          config['username'],
          config['password'] ?? '',
          config['port'] ?? 2638,
          config['enabled'] ?? 1,
          config['created_at'] ?? config['createdAt'],
          config['updated_at'] ?? config['updatedAt'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import Sybase config ${config['id']}: $e');
    }
  }
}

Future<void> _importPostgresConfigs(
  AppDatabase db,
  List<dynamic> configs,
) async {
  for (final c in configs) {
    final config = c as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO postgres_configs_table (
          id, name, host, port, database, username, password,
          enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          config['id'],
          config['name'],
          config['host'],
          config['port'] ?? 5432,
          config['database'],
          config['username'],
          config['password'] ?? '',
          config['enabled'] ?? 1,
          config['created_at'],
          config['updated_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import PostgreSQL config ${config['id']}: $e');
    }
  }
}

Future<void> _importDestinations(
  AppDatabase db,
  List<dynamic> destinations,
) async {
  for (final d in destinations) {
    final dest = d as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO backup_destinations_table (
          id, name, type, path, enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          dest['id'],
          dest['name'],
          dest['type'],
          dest['path'],
          dest['enabled'] ?? 1,
          dest['created_at'],
          dest['updated_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import destino ${dest['id']}: $e');
    }
  }
}

Future<void> _importEmailConfigs(
  AppDatabase db,
  List<dynamic> configs,
) async {
  for (final c in configs) {
    final config = c as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO email_configs_table (
          id, config_name, sender_name, from_email, from_name, smtp_server,
          smtp_port, username, password, smtp_password_key, auth_mode,
          oauth_provider, oauth_account_email, oauth_token_key,
          oauth_connected_at, use_ssl, recipients, notify_on_success,
          notify_on_error, notify_on_warning, attach_log, enabled,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          config['id'],
          config['config_name'] ?? 'Configuracao SMTP',
          config['sender_name'] ?? 'Sistema de Backup',
          config['from_email'] ?? 'backup@example.com',
          config['from_name'] ?? 'Sistema de Backup',
          config['smtp_server'] ?? 'smtp.gmail.com',
          config['smtp_port'] ?? 587,
          config['username'] ?? '',
          config['password'] ?? '',
          config['smtp_password_key'] ?? '',
          config['auth_mode'] ?? 'password',
          config['oauth_provider'],
          config['oauth_account_email'],
          config['oauth_token_key'],
          config['oauth_connected_at'],
          config['use_ssl'] ?? 1,
          config['recipients'] ?? '[]',
          config['notify_on_success'] ?? 1,
          config['notify_on_error'] ?? 1,
          config['notify_on_warning'] ?? 1,
          config['attach_log'] ?? 0,
          config['enabled'] ?? 1,
          config['created_at'],
          config['updated_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import email config ${config['id']}: $e');
    }
  }
}

Future<void> _importEmailTargets(
  AppDatabase db,
  List<dynamic> targets,
) async {
  for (final t in targets) {
    final target = t as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO email_notification_targets_table (
          id, email_config_id, recipient_email, notify_on_success,
          notify_on_error, notify_on_warning, enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          target['id'],
          target['email_config_id'],
          target['recipient_email'],
          target['notify_on_success'] ?? 1,
          target['notify_on_error'] ?? 1,
          target['notify_on_warning'] ?? 1,
          target['enabled'] ?? 1,
          target['created_at'],
          target['updated_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import email target ${target['id']}: $e');
    }
  }
}

Future<void> _importLicenses(
  AppDatabase db,
  List<dynamic> licenses,
) async {
  for (final l in licenses) {
    final license = l as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO licenses_table (
          id, license_key, machine_id, registered_name, email,
          is_active, expires_at, features, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          license['id'],
          license['license_key'],
          license['machine_id'],
          license['registered_name'],
          license['email'],
          license['is_active'] ?? 1,
          license['expires_at'],
          license['features'] ?? '[]',
          license['created_at'],
          license['updated_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import licença ${license['id']}: $e');
    }
  }
}

Future<void> _importSchedules(
  AppDatabase db,
  List<dynamic> schedules,
) async {
  for (final s in schedules) {
    final schedule = s as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO schedules_table (
          id, name, database_config_id, database_type, schedule_type,
          schedule_config, destination_ids, backup_folder, backup_type,
          truncate_log, compress_backup, compression_format, enabled,
          enable_checksum, verify_after_backup, post_backup_script,
          backup_timeout_seconds, verify_timeout_seconds, last_run_at,
          next_run_at, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          schedule['id'],
          schedule['name'],
          schedule['database_config_id'],
          schedule['database_type'],
          schedule['schedule_type'],
          schedule['schedule_config'],
          schedule['destination_ids'] ?? '[]',
          schedule['backup_folder'] ?? '',
          schedule['backup_type'] ?? 'full',
          schedule['truncate_log'] ?? 1,
          schedule['compress_backup'] ?? 0,
          schedule['compression_format'] ?? 'none',
          schedule['enabled'] ?? 1,
          schedule['enable_checksum'] ?? 0,
          schedule['verify_after_backup'] ?? 0,
          schedule['post_backup_script'],
          schedule['backup_timeout_seconds'] ?? 7200,
          schedule['verify_timeout_seconds'] ?? 1800,
          schedule['last_run_at'],
          schedule['next_run_at'],
          schedule['created_at'],
          schedule['updated_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import schedule ${schedule['id']}: $e');
    }
  }
}

Future<void> _importScheduleDestinations(
  AppDatabase db,
  List<dynamic> relations,
) async {
  for (final r in relations) {
    final rel = r as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO schedule_destinations_table (
          id, schedule_id, destination_id, created_at
        ) VALUES (?, ?, ?, ?)
        ''',
        [
          rel['id'],
          rel['schedule_id'],
          rel['destination_id'],
          rel['created_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import vínculo ${rel['id']}: $e');
    }
  }
}

Future<void> _importBackupHistory(
  AppDatabase db,
  List<dynamic> history,
) async {
  for (final h in history) {
    final item = h as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO backup_history_table (
          id, schedule_id, database_config_id, database_type, backup_type,
          started_at, finished_at, status, file_size, backup_file,
          error_message, destination_id, compression_format
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          item['id'],
          item['schedule_id'],
          item['database_config_id'],
          item['database_type'],
          item['backup_type'] ?? 'full',
          item['started_at'],
          item['finished_at'],
          item['status'],
          item['file_size'] ?? 0,
          item['backup_file'],
          item['error_message'],
          item['destination_id'],
          item['compression_format'] ?? 'none',
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import histórico ${item['id']}: $e');
    }
  }
}

Future<void> _importBackupLogs(
  AppDatabase db,
  List<dynamic> logs,
) async {
  for (final l in logs) {
    final log = l as Map<String, dynamic>;
    try {
      await db.customStatement(
        '''
        INSERT INTO backup_logs_table (
          id, backup_history_id, timestamp, level, message, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ''',
        [
          log['id'],
          log['backup_history_id'],
          log['timestamp'],
          log['level'],
          log['message'],
          log['created_at'],
        ],
      );
    } on Object catch (e) {
      LoggerService.warning('Import log ${log['id']}: $e');
    }
  }
}
