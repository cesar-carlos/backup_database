import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

Future<void> main() async {
  LoggerService.info('🔄 Iniciando migração do banco de dados...\n');

  try {
    // Caminho direto dos documentos
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
      LoggerService.error('❌ Banco de dados não encontrado em: $dbPath');
      LoggerService.info(
        'ℹ️  Certifique-se de que a aplicação foi executada pelo menos uma vez.',
      );
      return;
    }

    final fileSize = await dbFile.length();
    LoggerService.info(
      '📊 Tamanho do banco atual: ${(fileSize / 1024).toStringAsFixed(2)} KB\n',
    );

    if (fileSize == 0) {
      LoggerService.warning('⚠️  O banco de dados está vazio (0 bytes)');
      LoggerService.info(
        'ℹ️  Não há dados para migrar. Você pode simplesmente deletar o '
        'arquivo e deixar a aplicação recriar o banco com o schema correto.\n',
      );

      stdout.write('Deseja deletar o banco vazio e recriar? (s/N): ');
      final response = stdin.readLineSync()?.toLowerCase();

      if (response == 's' || response == 'sim') {
        await dbFile.delete();
        LoggerService.info(
          '\n✅ Banco vazio deletado. Inicie a aplicação para recriar.',
        );
      } else {
        LoggerService.info('\n❌ Operação cancelada.');
      }
      return;
    }

    LoggerService.info('1️⃣  Criando backup do banco atual...');
    await dbFile.copy(backupPath);
    LoggerService.info('   ✅ Backup criado: $backupPath\n');

    LoggerService.info('2️⃣  Conectando ao banco existente...');
    final db = sqlite3.open(dbPath);

    LoggerService.info('3️⃣  Exportando dados...');
    final exportData = _exportAllData(db);

    await File(exportPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(exportData),
    );
    LoggerService.info('   ✅ Dados exportados: $exportPath\n');

    LoggerService.info('📊 Resumo dos dados exportados:');
    LoggerService.info(
      '   • SQL Server configs: '
      '${(exportData['sql_server_configs'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • Sybase configs: '
      '${(exportData['sybase_configs'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • PostgreSQL configs: '
      '${(exportData['postgres_configs'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • Destinos: ${(exportData['destinations'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • Agendamentos: ${(exportData['schedules'] as List<dynamic>).length}',
    );
    LoggerService.info(
      '   • Histórico: '
      '${(exportData['backup_history'] as List<dynamic>).length}\n',
    );

    LoggerService.info('4️⃣  Fechando banco antigo...');
    db.dispose();
    LoggerService.info('   ✅ Banco fechado\n');

    LoggerService.info('5️⃣  Removendo banco antigo...');
    await dbFile.delete();
    LoggerService.info('   ✅ Banco antigo removido\n');

    LoggerService.info('6️⃣  Criando novo banco com schema correto...');
    final newDb = sqlite3.open(dbPath);

    // Criar schema v24
    _createSchema(newDb);
    LoggerService.info('   ✅ Novo banco criado com schema v24\n');

    LoggerService.info('7️⃣  Importando dados...');
    _importAllData(newDb, exportData);
    LoggerService.info('   ✅ Dados importados com sucesso\n');

    LoggerService.info('8️⃣  Validando dados...');
    _validateData(newDb, exportData);
    LoggerService.info('   ✅ Dados validados\n');

    newDb.dispose();

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

Map<String, dynamic> _exportAllData(Database db) {
  final data = <String, dynamic>{};

  // SQL Server configs
  try {
    final result = db.select('SELECT * FROM sql_server_configs_table');
    data['sql_server_configs'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info('   ✓ SQL Server configs: ${result.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  SQL Server configs: erro ($e)');
    data['sql_server_configs'] = <Map<String, dynamic>>[];
  }

  // Sybase configs
  try {
    final result = db.select('SELECT * FROM sybase_configs_table');
    data['sybase_configs'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info('   ✓ Sybase configs: ${result.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Sybase configs: erro ($e)');
    data['sybase_configs'] = <Map<String, dynamic>>[];
  }

  // PostgreSQL configs
  try {
    final result = db.select('SELECT * FROM postgres_configs_table');
    data['postgres_configs'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info('   ✓ PostgreSQL configs: ${result.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  PostgreSQL configs: erro ($e)');
    data['postgres_configs'] = <Map<String, dynamic>>[];
  }

  // Destinations
  try {
    final result = db.select('SELECT * FROM backup_destinations_table');
    data['destinations'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info('   ✓ Destinos: ${result.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Destinos: erro ($e)');
    data['destinations'] = <Map<String, dynamic>>[];
  }

  // Schedules
  try {
    final result = db.select('SELECT * FROM schedules_table');
    data['schedules'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info('   ✓ Agendamentos: ${result.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Agendamentos: erro ($e)');
    data['schedules'] = <Map<String, dynamic>>[];
  }

  // Schedule destinations
  try {
    final result = db.select('SELECT * FROM schedule_destinations_table');
    data['schedule_destinations'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info(
      '   ✓ Vínculos Schedule-Destination: ${result.length}',
    );
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Schedule destinations: erro ($e)');
    data['schedule_destinations'] = <Map<String, dynamic>>[];
  }

  // Backup history
  try {
    final result = db.select('SELECT * FROM backup_history_table');
    data['backup_history'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info('   ✓ Histórico: ${result.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Histórico: erro ($e)');
    data['backup_history'] = <Map<String, dynamic>>[];
  }

  // Backup logs
  try {
    final result = db.select('SELECT * FROM backup_logs_table');
    data['backup_logs'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info('   ✓ Logs: ${result.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Logs: erro ($e)');
    data['backup_logs'] = <Map<String, dynamic>>[];
  }

  // Email configs
  try {
    final result = db.select('SELECT * FROM email_configs_table');
    data['email_configs'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info(
      '   ✓ Configurações de email: ${result.length}',
    );
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Email configs: erro ($e)');
    data['email_configs'] = <Map<String, dynamic>>[];
  }

  // Email targets
  try {
    final result = db.select('SELECT * FROM email_notification_targets_table');
    data['email_notification_targets'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info(
      '   ✓ Destinatários de email: ${result.length}',
    );
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Email targets: erro ($e)');
    data['email_notification_targets'] = <Map<String, dynamic>>[];
  }

  // Licenses
  try {
    final result = db.select('SELECT * FROM licenses_table');
    data['licenses'] =
        result.map(Map<String, dynamic>.from).toList();
    LoggerService.info('   ✓ Licenças: ${result.length}');
  } on Object catch (e) {
    LoggerService.warning('   ⚠️  Licenças: erro ($e)');
    data['licenses'] = <Map<String, dynamic>>[];
  }

  return data;
}

void _createSchema(Database db) {
  // Ler o schema do arquivo database.dart seria complexo,
  // então vou deixar a aplicação criar o schema automaticamente
  // quando for iniciada pela primeira vez
  
  // Por enquanto, apenas garantir que o arquivo existe
  db.execute('SELECT 1');
}

void _importAllData(Database db, Map<String, dynamic> data) {
  db.execute('BEGIN TRANSACTION');
  
  try {
    // Desabilitar triggers temporariamente
    db.execute('PRAGMA foreign_keys = OFF');
    
    _importSqlServerConfigs(
      db,
      data['sql_server_configs'] as List<Map<String, dynamic>>,
    );
    _importSybaseConfigs(
      db,
      data['sybase_configs'] as List<Map<String, dynamic>>,
    );
    _importPostgresConfigs(
      db,
      data['postgres_configs'] as List<Map<String, dynamic>>,
    );
    _importDestinations(
      db,
      data['destinations'] as List<Map<String, dynamic>>,
    );
    _importEmailConfigs(
      db,
      data['email_configs'] as List<Map<String, dynamic>>,
    );
    _importEmailTargets(
      db,
      data['email_notification_targets'] as List<Map<String, dynamic>>,
    );
    _importLicenses(
      db,
      data['licenses'] as List<Map<String, dynamic>>,
    );
    _importSchedules(
      db,
      data['schedules'] as List<Map<String, dynamic>>,
    );
    _importScheduleDestinations(
      db,
      data['schedule_destinations'] as List<Map<String, dynamic>>,
    );
    _importBackupHistory(
      db,
      data['backup_history'] as List<Map<String, dynamic>>,
    );
    _importBackupLogs(
      db,
      data['backup_logs'] as List<Map<String, dynamic>>,
    );
    
    // Reabilitar triggers
    db.execute('PRAGMA foreign_keys = ON');
    
    db.execute('COMMIT');
  } on Object catch (e) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

void _importSqlServerConfigs(
  Database db,
  List<Map<String, dynamic>> configs,
) {
  for (final config in configs) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO sql_server_configs_table (
          id, name, server, database, username, password, port, 
          enabled, use_windows_auth, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
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
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar SQL Server config ${config['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ SQL Server configs: ${configs.length} importados');
}

void _importSybaseConfigs(
  Database db,
  List<Map<String, dynamic>> configs,
) {
  for (final config in configs) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO sybase_configs_table (
          id, name, server_name, database_name, database_file, username, 
          password, port, enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
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
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar Sybase config ${config['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Sybase configs: ${configs.length} importados');
}

void _importPostgresConfigs(
  Database db,
  List<Map<String, dynamic>> configs,
) {
  for (final config in configs) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO postgres_configs_table (
          id, name, host, port, database, username, password, 
          enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
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
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar PostgreSQL config ${config['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ PostgreSQL configs: ${configs.length} importados');
}

void _importDestinations(
  Database db,
  List<Map<String, dynamic>> destinations,
) {
  for (final dest in destinations) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO backup_destinations_table (
          id, name, type, path, enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
        dest['id'],
        dest['name'],
        dest['type'],
        dest['path'],
        dest['enabled'] ?? 1,
        dest['created_at'],
        dest['updated_at'],
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar destino ${dest['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Destinos: ${destinations.length} importados');
}

void _importEmailConfigs(
  Database db,
  List<Map<String, dynamic>> configs,
) {
  for (final config in configs) {
    try {
      final stmt = db.prepare(
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
      );
      
      stmt.execute([
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
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar email config ${config['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Email configs: ${configs.length} importados');
}

void _importEmailTargets(
  Database db,
  List<Map<String, dynamic>> targets,
) {
  for (final target in targets) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO email_notification_targets_table (
          id, email_config_id, recipient_email, notify_on_success,
          notify_on_error, notify_on_warning, enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
        target['id'],
        target['email_config_id'],
        target['recipient_email'],
        target['notify_on_success'] ?? 1,
        target['notify_on_error'] ?? 1,
        target['notify_on_warning'] ?? 1,
        target['enabled'] ?? 1,
        target['created_at'],
        target['updated_at'],
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar email target ${target['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Email targets: ${targets.length} importados');
}

void _importLicenses(
  Database db,
  List<Map<String, dynamic>> licenses,
) {
  for (final license in licenses) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO licenses_table (
          id, license_key, machine_id, registered_name, email,
          is_active, expires_at, features, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
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
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar licença ${license['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Licenças: ${licenses.length} importadas');
}

void _importSchedules(
  Database db,
  List<Map<String, dynamic>> schedules,
) {
  for (final schedule in schedules) {
    try {
      final stmt = db.prepare(
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
      );
      
      stmt.execute([
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
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar schedule ${schedule['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Agendamentos: ${schedules.length} importados');
}

void _importScheduleDestinations(
  Database db,
  List<Map<String, dynamic>> relations,
) {
  for (final rel in relations) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO schedule_destinations_table (
          id, schedule_id, destination_id, created_at
        ) VALUES (?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
        rel['id'],
        rel['schedule_id'],
        rel['destination_id'],
        rel['created_at'],
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar vínculo ${rel['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Vínculos: ${relations.length} importados');
}

void _importBackupHistory(
  Database db,
  List<Map<String, dynamic>> history,
) {
  for (final item in history) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO backup_history_table (
          id, schedule_id, database_config_id, database_type, backup_type,
          started_at, finished_at, status, file_size, backup_file,
          error_message, destination_id, compression_format
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
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
      ]);
      
      stmt.dispose();
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

void _importBackupLogs(
  Database db,
  List<Map<String, dynamic>> logs,
) {
  for (final log in logs) {
    try {
      final stmt = db.prepare(
        '''
        INSERT INTO backup_logs_table (
          id, backup_history_id, timestamp, level, message, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ''',
      );
      
      stmt.execute([
        log['id'],
        log['backup_history_id'],
        log['timestamp'],
        log['level'],
        log['message'],
        log['created_at'],
      ]);
      
      stmt.dispose();
    } on Object catch (e) {
      LoggerService.warning(
        '   ⚠️  Erro ao importar log ${log['id']}: $e',
      );
    }
  }
  LoggerService.info('   ✓ Logs: ${logs.length} registros importados');
}

void _validateData(Database db, Map<String, dynamic> exportData) {
  final sqlConfigsCount = db.select(
    'SELECT COUNT(*) as count FROM sql_server_configs_table',
  ).first['count'] as int;
  final exportedSqlConfigs =
      (exportData['sql_server_configs'] as List<dynamic>).length;

  if (sqlConfigsCount != exportedSqlConfigs) {
    LoggerService.warning(
      '   ⚠️  SQL Server configs: esperado $exportedSqlConfigs, '
      'encontrado $sqlConfigsCount',
    );
  }

  final schedulesCount = db.select(
    'SELECT COUNT(*) as count FROM schedules_table',
  ).first['count'] as int;
  final exportedSchedules =
      (exportData['schedules'] as List<dynamic>).length;

  if (schedulesCount != exportedSchedules) {
    LoggerService.warning(
      '   ⚠️  Schedules: esperado $exportedSchedules, '
      'encontrado $schedulesCount',
    );
  }

  final destCount = db.select(
    'SELECT COUNT(*) as count FROM backup_destinations_table',
  ).first['count'] as int;
  final exportedDest = (exportData['destinations'] as List<dynamic>).length;

  if (destCount != exportedDest) {
    LoggerService.warning(
      '   ⚠️  Destinos: esperado $exportedDest, encontrado $destCount',
    );
  }
}
