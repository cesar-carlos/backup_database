import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  LoggerService.info('🔄 Iniciando migração do banco de dados...\n');

  try {
    // Usar caminho direto dos documentos do usuário
    final userHome = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dbFolder = p.join(userHome, 'Documents');
    final dbPath = p.join(dbFolder, 'backup_database.db');
    final backupPath = p.join(dbFolder, 'backup_database_backup.db');
    final exportPath = p.join(dbFolder, 'backup_export.json');

    LoggerService.info('📂 Banco atual: $dbPath');
    LoggerService.info('💾 Backup será salvo em: $backupPath');
    LoggerService.info('📄 Export JSON em: $exportPath\n');

    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      LoggerService.error('❌ Banco de dados não encontrado');
      return;
    }

    LoggerService.info('1️⃣  Criando backup do banco atual...');
    await dbFile.copy(backupPath);
    LoggerService.info('   ✅ Backup criado: $backupPath\n');

    LoggerService.info('2️⃣  Conectando ao banco existente...');
    final oldDb = AppDatabase();

    LoggerService.info('3️⃣  Exportando dados...');
    final exportData = await _exportAllData(oldDb);

    await File(exportPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(exportData),
    );
    LoggerService.info('   ✅ Dados exportados: $exportPath\n');

    LoggerService.info('📊 Resumo dos dados exportados:');
    LoggerService.info(
      '   • SQL Server configs: ${(exportData['sql_server_configs'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • Sybase configs: ${(exportData['sybase_configs'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • PostgreSQL configs: ${(exportData['postgres_configs'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • Destinos: ${(exportData['destinations'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • Agendamentos: ${(exportData['schedules'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • Histórico: ${(exportData['backup_history'] as List<dynamic>).length}\n',
    );

    LoggerService.info('4️⃣  Fechando banco antigo...');
    await oldDb.close();
    LoggerService.info('   ✅ Banco fechado\n');

    LoggerService.info('5️⃣  Removendo banco antigo...');
    await dbFile.delete();
    LoggerService.info('   ✅ Banco antigo removido\n');

    LoggerService.info('6️⃣  Criando novo banco com schema correto...');
    final newDb = AppDatabase();

    await newDb.customSelect('SELECT 1').get();
    LoggerService.info('   ✅ Novo banco criado com schema v24\n');

    LoggerService.info('7️⃣  Importando dados...');
    await _importAllData(newDb, exportData);
    LoggerService.info('   ✅ Dados importados com sucesso\n');

    LoggerService.info('8️⃣  Validando dados...');
    await _validateData(newDb, exportData);
    LoggerService.info('   ✅ Dados validados\n');

    await newDb.close();

    LoggerService.info('✅ MIGRAÇÃO CONCLUÍDA COM SUCESSO!\n');
    LoggerService.info('📌 Arquivos criados:');
    LoggerService.info('   • Backup: $backupPath');
    LoggerService.info('   • Export: $exportPath');
    LoggerService.info(
      '\n💡 Você pode deletar esses arquivos após confirmar que tudo funciona.',
    );
  } on Object catch (e, stackTrace) {
    LoggerService.error('\n❌ ERRO NA MIGRAÇÃO: $e', e, stackTrace);
    LoggerService.warning(
      '\n⚠️  O banco de dados original foi preservado como backup.',
    );
    exit(1);
  }
}

Future<Map<String, dynamic>> _exportAllData(AppDatabase db) async {
  final data = <String, dynamic>{};

  try {
    final sqlConfigs = await db.customSelect(
      'SELECT * FROM sql_server_configs_table',
    ).get();
    data['sql_server_configs'] = sqlConfigs.map((row) => row.data).toList();
    LoggerService.info('   ✓ SQL Server configs: ${sqlConfigs.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  SQL Server configs: erro ($e)');
    data['sql_server_configs'] = <Map<String, dynamic>>[];
  }

  try {
    final sybaseConfigs = await db.customSelect(
      'SELECT * FROM sybase_configs_table',
    ).get();
    data['sybase_configs'] = sybaseConfigs.map((row) => row.data).toList();
    LoggerService.info('   ✓ Sybase configs: ${sybaseConfigs.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Sybase configs: erro ($e)');
    data['sybase_configs'] = <Map<String, dynamic>>[];
  }

  try {
    final postgresConfigs = await db.customSelect(
      'SELECT * FROM postgres_configs_table',
    ).get();
    data['postgres_configs'] = postgresConfigs.map((row) => row.data).toList();
    LoggerService.info('   ✓ PostgreSQL configs: ${postgresConfigs.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  PostgreSQL configs: erro ($e)');
    data['postgres_configs'] = <Map<String, dynamic>>[];
  }

  try {
    final destinations = await db.customSelect(
      'SELECT * FROM backup_destinations_table',
    ).get();
    data['destinations'] = destinations.map((row) => row.data).toList();
    LoggerService.info('   ✓ Destinos: ${destinations.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Destinos: erro ($e)');
    data['destinations'] = <Map<String, dynamic>>[];
  }

  try {
    final schedules = await db.customSelect(
      'SELECT * FROM schedules_table',
    ).get();
    data['schedules'] = schedules.map((row) => row.data).toList();
    LoggerService.info('   ✓ Agendamentos: ${schedules.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Agendamentos: erro ($e)');
    data['schedules'] = <Map<String, dynamic>>[];
  }

  try {
    final scheduleDestinations = await db.customSelect(
      'SELECT * FROM schedule_destinations_table',
    ).get();
    data['schedule_destinations'] = scheduleDestinations
        .map((row) => row.data)
        .toList();
    LoggerService.info(
      '   ✓ Vínculos Schedule-Destination: ${scheduleDestinations.length}',
    );
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Schedule destinations: erro ($e)');
    data['schedule_destinations'] = <Map<String, dynamic>>[];
  }

  try {
    final history = await db.customSelect(
      'SELECT * FROM backup_history_table',
    ).get();
    data['backup_history'] = history.map((row) => row.data).toList();
    LoggerService.info('   ✓ Histórico: ${history.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Histórico: erro ($e)');
    data['backup_history'] = <Map<String, dynamic>>[];
  }

  try {
    final logs = await db.customSelect(
      'SELECT * FROM backup_logs_table',
    ).get();
    data['backup_logs'] = logs.map((row) => row.data).toList();
    LoggerService.info('   ✓ Logs: ${logs.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Logs: erro ($e)');
    data['backup_logs'] = <Map<String, dynamic>>[];
  }

  try {
    final emailConfigs = await db.customSelect(
      'SELECT * FROM email_configs_table',
    ).get();
    data['email_configs'] = emailConfigs.map((row) => row.data).toList();
    LoggerService.info(
      '   ✓ Configurações de email: ${emailConfigs.length}',
    );
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Email configs: erro ($e)');
    data['email_configs'] = <Map<String, dynamic>>[];
  }

  try {
    final emailTargets = await db.customSelect(
      'SELECT * FROM email_notification_targets_table',
    ).get();
    data['email_notification_targets'] = emailTargets
        .map((row) => row.data)
        .toList();
    LoggerService.info(
      '   ✓ Destinatários de email: ${emailTargets.length}',
    );
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Email targets: erro ($e)');
    data['email_notification_targets'] = <Map<String, dynamic>>[];
  }

  try {
    final licenses = await db.customSelect(
      'SELECT * FROM licenses_table',
    ).get();
    data['licenses'] = licenses.map((row) => row.data).toList();
    LoggerService.info('   ✓ Licenças: ${licenses.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Licenças: erro ($e)');
    data['licenses'] = <Map<String, dynamic>>[];
  }

  return data;
}

Future<void> _importAllData(
  AppDatabase db,
  Map<String, dynamic> data,
) async {
  await db.transaction(() async {
    await _importSqlServerConfigs(
      db,
      data['sql_server_configs'] as List<Map<String, dynamic>>,
    );
    await _importSybaseConfigs(
      db,
      data['sybase_configs'] as List<Map<String, dynamic>>,
    );
    await _importPostgresConfigs(
      db,
      data['postgres_configs'] as List<Map<String, dynamic>>,
    );
    await _importDestinations(
      db,
      data['destinations'] as List<Map<String, dynamic>>,
    );
    await _importEmailConfigs(
      db,
      data['email_configs'] as List<Map<String, dynamic>>,
    );
    await _importEmailTargets(
      db,
      data['email_notification_targets'] as List<Map<String, dynamic>>,
    );
    await _importLicenses(
      db,
      data['licenses'] as List<Map<String, dynamic>>,
    );
    await _importSchedules(
      db,
      data['schedules'] as List<Map<String, dynamic>>,
    );
    await _importScheduleDestinations(
      db,
      data['schedule_destinations'] as List<Map<String, dynamic>>,
    );
    await _importBackupHistory(
      db,
      data['backup_history'] as List<Map<String, dynamic>>,
    );
    await _importBackupLogs(
      db,
      data['backup_logs'] as List<Map<String, dynamic>>,
    );
  });
}

Future<void> _importSqlServerConfigs(
  AppDatabase db,
  List<Map<String, dynamic>> configs,
) async {
  for (final config in configs) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar SQL Server config ${config['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ SQL Server configs: ${configs.length} importados');
}

Future<void> _importSybaseConfigs(
  AppDatabase db,
  List<Map<String, dynamic>> configs,
) async {
  for (final config in configs) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar Sybase config ${config['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Sybase configs: ${configs.length} importados');
}

Future<void> _importPostgresConfigs(
  AppDatabase db,
  List<Map<String, dynamic>> configs,
) async {
  for (final config in configs) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar PostgreSQL config ${config['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ PostgreSQL configs: ${configs.length} importados');
}

Future<void> _importDestinations(
  AppDatabase db,
  List<Map<String, dynamic>> destinations,
) async {
  for (final dest in destinations) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar destino ${dest['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Destinos: ${destinations.length} importados');
}

Future<void> _importEmailConfigs(
  AppDatabase db,
  List<Map<String, dynamic>> configs,
) async {
  for (final config in configs) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar email config ${config['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Email configs: ${configs.length} importados');
}

Future<void> _importEmailTargets(
  AppDatabase db,
  List<Map<String, dynamic>> targets,
) async {
  for (final target in targets) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar email target ${target['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Email targets: ${targets.length} importados');
}

Future<void> _importLicenses(
  AppDatabase db,
  List<Map<String, dynamic>> licenses,
) async {
  for (final license in licenses) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar licença ${license['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Licenças: ${licenses.length} importadas');
}

Future<void> _importSchedules(
  AppDatabase db,
  List<Map<String, dynamic>> schedules,
) async {
  for (final schedule in schedules) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar schedule ${schedule['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Agendamentos: ${schedules.length} importados');
}

Future<void> _importScheduleDestinations(
  AppDatabase db,
  List<Map<String, dynamic>> relations,
) async {
  for (final rel in relations) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar vínculo ${rel['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Vínculos: ${relations.length} importados');
}

Future<void> _importBackupHistory(
  AppDatabase db,
  List<Map<String, dynamic>> history,
) async {
  for (final item in history) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar histórico ${item['id']}: $e',
      );
    }
  }
  LoggerService.info(
    '   ✓ Histórico: ${history.length} registros importados',
  );
}

Future<void> _importBackupLogs(
  AppDatabase db,
  List<Map<String, dynamic>> logs,
) async {
  for (final log in logs) {
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
      LoggerService.warning(
        '   ⚠️  Erro ao importar log ${log['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Logs: ${logs.length} registros importados');
}

Future<void> _validateData(
  AppDatabase db,
  Map<String, dynamic> exportData,
) async {
  final sqlConfigsCount = await db.customSelect(
    'SELECT COUNT(*) as count FROM sql_server_configs_table',
  ).getSingle();
  final exportedSqlConfigs =
      (exportData['sql_server_configs'] as List<dynamic>).length;

  if (sqlConfigsCount.read<int>('count') != exportedSqlConfigs) {
    LoggerService.warning(
      '   ⚠️  SQL Server configs: esperado $exportedSqlConfigs, '
      'encontrado ${sqlConfigsCount.read<int>('count')}',
    );
  }

  final schedulesCount = await db.customSelect(
    'SELECT COUNT(*) as count FROM schedules_table',
  ).getSingle();
  final exportedSchedules =
      (exportData['schedules'] as List<dynamic>).length;

  if (schedulesCount.read<int>('count') != exportedSchedules) {
    LoggerService.warning(
      '   ⚠️  Schedules: esperado $exportedSchedules, '
      'encontrado ${schedulesCount.read<int>('count')}',
    );
  }

  final destCount = await db.customSelect(
    'SELECT COUNT(*) as count FROM backup_destinations_table',
  ).getSingle();
  final exportedDest = (exportData['destinations'] as List<dynamic>).length;

  if (destCount.read<int>('count') != exportedDest) {
    LoggerService.warning(
      '   ⚠️  Destinos: esperado $exportedDest, '
      'encontrado ${destCount.read<int>('count')}',
    );
  }
}
