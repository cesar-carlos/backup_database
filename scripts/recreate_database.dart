import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  LoggerService.info('🔄 Recriando banco de dados do zero...\n');
  LoggerService.warning(
    '⚠️  ATENÇÃO: Este script irá DELETAR todos os dados existentes!\n',
  );

  stdout.write('Tem certeza que deseja continuar? (s/N): ');
  final response = stdin.readLineSync()?.toLowerCase();

  if (response != 's' && response != 'sim') {
    LoggerService.info('\n❌ Operação cancelada pelo usuário.');
    return;
  }

  try {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dbFolder.path, 'backup_database.db');
    final backupPath = p.join(dbFolder.path, 'backup_database_old.db');

    LoggerService.info('\n📂 Banco atual: $dbPath\n');

    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      LoggerService.info(
        'ℹ️  Banco de dados não existe. Criando novo banco...\n',
      );
    } else {
      LoggerService.info('1️⃣  Fazendo backup do banco atual...');
      await dbFile.copy(backupPath);
      LoggerService.info('   ✅ Backup criado: $backupPath\n');

      LoggerService.info('2️⃣  Removendo banco antigo...');
      await dbFile.delete();
      LoggerService.info('   ✅ Banco removido\n');
    }

    LoggerService.info('3️⃣  Criando novo banco com schema v24...');
    final db = AppDatabase();

    await db.customSelect('SELECT 1').get();
    LoggerService.info('   ✅ Novo banco criado\n');

    LoggerService.info('4️⃣  Verificando estrutura...');
    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    ).get();

    LoggerService.info('   📊 Tabelas criadas:');
    for (final table in tables) {
      final tableName = table.read<String>('name');
      if (!tableName.startsWith('sqlite_')) {
        final count = await db.customSelect(
          'SELECT COUNT(*) as count FROM $tableName',
        ).getSingle();
        LoggerService.info(
          '      • $tableName (${count.read<int>('count')} registros)',
        );
      }
    }

    LoggerService.info('\n   ✅ Estrutura validada\n');

    await db.close();

    LoggerService.info('✅ BANCO RECRIADO COM SUCESSO!\n');
    LoggerService.info('📌 Próximos passos:');
    LoggerService.info('   1. Inicie a aplicação');
    LoggerService.info('   2. Configure novamente seus bancos de dados');
    LoggerService.info('   3. Configure destinos de backup');
    LoggerService.info('   4. Crie seus agendamentos\n');

    if (File(backupPath).existsSync()) {
      LoggerService.info('💡 Backup do banco antigo salvo em:');
      LoggerService.info('   $backupPath\n');
    }
  } on Object catch (e, stackTrace) {
    LoggerService.error('\n❌ ERRO: $e', e, stackTrace);
    exit(1);
  }
}
