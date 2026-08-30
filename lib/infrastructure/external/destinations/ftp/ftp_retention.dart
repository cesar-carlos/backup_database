import 'package:backup_database/core/errors/ftp_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FtpRetention {
  Future<rd.Result<int>> cleanOldBackups({
    required FtpDestinationConfig config,
  }) async {
    try {
      LoggerService.info('Limpando backups antigos no FTP: ${config.host}');

      final ftp = FTPConnect(
        config.host,
        port: config.port,
        user: config.username,
        pass: config.password,
        timeout: config.effectiveUploadTimeoutSeconds,
        securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
        allowInvalidCertificates: config.allowInvalidCertificates,
        showLog: config.enableVerboseLog || kDebugMode,
      );

      final connected = await ftp.connect();
      if (!connected) {
        return const rd.Failure(
          FtpFailure(message: 'Falha ao conectar ao FTP'),
        );
      }

      if (config.remotePath.isNotEmpty) {
        try {
          await ftp.changeDirectory(config.remotePath);
        } on Object catch (e) {
          LoggerService.debug(
            'Diretório remoto não existe, sem backups para limpar: ${config.remotePath} — $e',
          );
          await ftp.disconnect();
          return const rd.Success(0);
        }
      }

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      var deletedCount = 0;
      final items = await ftp.listDirectoryContent();

      for (final item in items) {
        if (item.type == FTPEntryType.file) {
          try {
            final fileName = item.name;

            if (SybaseBackupPathSuffix.isPathProtected(
              fileName,
              config.protectedBackupIdShortPrefixes,
            )) {
              LoggerService.debug(
                'Arquivo FTP protegido (retenção Sybase): $fileName',
              );
              continue;
            }

            final datePattern = RegExp(r'(\d{4}-\d{2}-\d{2})');
            final match = datePattern.firstMatch(fileName);

            if (match != null) {
              final dateStr = match.group(1)!;
              final fileDate = DateTime.parse(dateStr);

              if (fileDate.isBefore(cutoffDate)) {
                await ftp.deleteFile(fileName);
                deletedCount++;
                LoggerService.debug('Arquivo FTP removido: $fileName');
              }
            }
          } on Object catch (e) {
            LoggerService.debug(
              'Não foi possível extrair data do arquivo ${item.name}: $e',
            );
          }
        }
      }

      await ftp.disconnect();
      LoggerService.info('$deletedCount arquivos antigos removidos do FTP');
      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao limpar backups FTP', e, stackTrace);
      return rd.Failure(
        FtpFailure(message: 'Erro ao limpar backups FTP: $e', originalError: e),
      );
    }
  }
}
