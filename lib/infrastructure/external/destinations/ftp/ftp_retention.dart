import 'package:backup_database/core/errors/ftp_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FtpRetention {
  FtpRetention({
    this._clientFactory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final FTPConnect Function(FtpDestinationConfig)? _clientFactory;
  final DateTime Function() _clock;

  Future<rd.Result<int>> cleanOldBackups({
    required FtpDestinationConfig config,
  }) async {
    FTPConnect? ftp;
    try {
      LoggerService.info('Limpando backups antigos no FTP: ${config.host}');

      ftp =
          _clientFactory?.call(config) ??
          FTPConnect(
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
          if (!await ftp.changeDirectory(config.remotePath)) {
            throw const FtpFailure(
              message: 'Diretório FTP de retenção inacessível.',
            );
          }
        } on Object catch (e) {
          LoggerService.debug(
            'Não foi possível acessar o diretório FTP de retenção: ${config.remotePath} — $e',
          );
          rethrow;
        }
      }

      final cutoffDate = _clock().subtract(
        Duration(days: config.retentionDays),
      );

      var deletedCount = 0;
      final items = await ftp.listDirectoryContent();

      for (final item in items) {
        if (item.type == FTPEntryType.file) {
          try {
            final fileName = item.name;
            if (fileName.toLowerCase().endsWith('.part')) {
              // A restarted upload may have an old backup date but fresh data.
              final modified = item.modifyTime;
              if (modified == null || !modified.isBefore(cutoffDate)) continue;
            }

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
              final fileDate = DateTime.tryParse(dateStr);
              if (fileDate == null ||
                  fileDate.toIso8601String().substring(0, 10) != dateStr) {
                continue;
              }

              if (fileDate.isBefore(cutoffDate)) {
                if (!await ftp.deleteFile(fileName)) {
                  throw const FtpFailure(
                    message: 'FTP recusou a exclusão na retenção.',
                  );
                }
                deletedCount++;
                LoggerService.debug('Arquivo FTP removido: $fileName');
              }
            }
          } on Object catch (e) {
            LoggerService.debug(
              'Não foi possível processar a retenção do arquivo ${item.name}: $e',
            );
          }
        }
      }

      LoggerService.info('$deletedCount arquivos antigos removidos do FTP');
      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao limpar backups FTP', e, stackTrace);
      return rd.Failure(
        FtpFailure(message: 'Erro ao limpar backups FTP: $e', originalError: e),
      );
    } finally {
      ftp?.abort();
    }
  }
}
