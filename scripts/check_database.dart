import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  try {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dbFolder.path, 'backup_database.db');

    LoggerService.info('📂 Database path: $dbPath');

    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      LoggerService.error('❌ Database file does not exist');
      return;
    }

    final dbSize = dbFile.lengthSync();
    LoggerService.info(
      '📊 Database size: ${(dbSize / 1024).toStringAsFixed(2)} KB',
    );

    final database = AppDatabase();

    final tables = await database
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name",
        )
        .get();

    LoggerService.info('\n📋 Tables (${tables.length}):');
    for (final table in tables) {
      final name = table.read<String>('name');
      LoggerService.info('  ✓ $name');
    }

    final version = await database.customSelect('PRAGMA user_version').get();
    final schemaVersion = version.first.read<int>('user_version');
    LoggerService.info('\n🔢 Schema version: $schemaVersion (expected: 24)');

    final sqlConfigs = await database
        .customSelect(
          'SELECT COUNT(*) as count FROM sql_server_configs_table',
        )
        .get();
    LoggerService.info(
      '\n🗄️  SQL Server configs: ${sqlConfigs.first.read<int>('count')}',
    );

    final sybaseConfigs = await database
        .customSelect(
          'SELECT COUNT(*) as count FROM sybase_configs_table',
        )
        .get();
    LoggerService.info(
      '🗄️  Sybase configs: ${sybaseConfigs.first.read<int>('count')}',
    );

    final postgresConfigs = await database
        .customSelect(
          'SELECT COUNT(*) as count FROM postgres_configs_table',
        )
        .get();
    LoggerService.info(
      '🗄️  PostgreSQL configs: ${postgresConfigs.first.read<int>('count')}',
    );

    final schedules = await database
        .customSelect(
          'SELECT COUNT(*) as count FROM schedules_table',
        )
        .get();
    LoggerService.info('📅 Schedules: ${schedules.first.read<int>('count')}');

    await database.close();
    LoggerService.info('\n✅ Database check completed');
  } on Object catch (e, stackTrace) {
    LoggerService.error('❌ Error: $e', e, stackTrace);
  }
}
