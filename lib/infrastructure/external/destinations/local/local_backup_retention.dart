import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class LocalBackupRetention {
  const LocalBackupRetention();

  /// Extensões reconhecidas como "arquivos de backup" (ou seus
  /// derivados). Apenas arquivos cuja extensão termine com um destes
  /// sufixos serão considerados pelo `cleanOldBackups`. Antes, o cleanup
  /// apagava QUALQUER arquivo antigo na pasta — se o usuário tinha
  /// outros arquivos lá, eram perdidos.
  static const Set<String> _backupFileExtensions = {
    '.bak', // SQL Server
    '.trn', // SQL Server transaction log
    '.dump', // PostgreSQL pg_dump
    '.backup', // PostgreSQL backup
    '.tar', // PostgreSQL pg_basebackup tar
    '.db', // Sybase SA database file (usado em backups full)
    '.log', // Sybase transaction log
    '.sql', // SQL dump genérico
    '.zip',
    '.7z',
    '.gz',
    '.rar',
    '.bz2',
    '.xz',
    '.zst',
  };

  /// Identifica se o arquivo parece ser um artefato de backup (por
  /// extensão). Filtra `.tmp` (uploads em andamento) e qualquer outro
  /// arquivo que o usuário possa ter na pasta.
  static bool _looksLikeBackupArtifact(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.tmp')) return false;
    return _backupFileExtensions.any(lower.endsWith);
  }

  Future<rd.Result<int>> cleanOldBackups({
    required LocalDestinationConfig config,
  }) async {
    try {
      LoggerService.info('Limpando backups antigos em: ${config.path}');

      final directory = Directory(config.path);
      if (!await directory.exists()) {
        return const rd.Success(0);
      }

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );
      final protected = config.protectedBackupIdShortPrefixes;

      var deletedCount = 0;
      var skippedNonBackup = 0;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is! File) continue;
        // Filtro por extensão: protege arquivos do usuário que estejam
        // na mesma pasta (configurações, anotações, etc.).
        if (!_looksLikeBackupArtifact(p.basename(entity.path))) {
          skippedNonBackup++;
          continue;
        }
        if (protected.isNotEmpty &&
            SybaseBackupPathSuffix.isPathProtected(entity.path, protected)) {
          LoggerService.debug(
            'Arquivo protegido (cadeia Sybase): ${entity.path}',
          );
          continue;
        }
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoffDate)) {
          await entity.delete();
          deletedCount++;
          LoggerService.debug('Arquivo deletado: ${entity.path}');
        }
      }

      await for (final entity in directory.list()) {
        if (entity is Directory) {
          final contents = await entity.list().toList();
          if (contents.isEmpty) {
            if (protected.isNotEmpty &&
                SybaseBackupPathSuffix.isPathProtected(
                  entity.path,
                  protected,
                )) {
              LoggerService.debug(
                'Diretório protegido (cadeia Sybase): ${entity.path}',
              );
              continue;
            }
            await entity.delete();
            LoggerService.debug('Diretório vazio removido: ${entity.path}');
          }
        }
      }

      LoggerService.info(
        '$deletedCount arquivo(s) antigo(s) removido(s) '
        '($skippedNonBackup arquivo(s) não-backup preservado(s))',
      );
      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao limpar backups antigos', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao limpar backups antigos: $e',
          originalError: e,
        ),
      );
    }
  }
}
