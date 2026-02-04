import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure.dart' hide FtpFailure;
import 'package:backup_database/core/errors/ftp_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class FtpDestinationService implements IFtpService {
  @override
  Future<rd.Result<FtpUploadResult>> upload({
    required String sourceFilePath,
    required FtpDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
    UploadProgressCallback? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Enviando para FTP: ${config.host}');

      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Arquivo de origem não encontrado: $sourceFilePath',
          ),
        );
      }

      final fileSize = await sourceFile.length();
      final fileName = customFileName ?? p.basename(sourceFilePath);

      Exception? lastError;
      final failedAttempts = <String>[];
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        FTPConnect? ftp;
        try {
          LoggerService.debug('Tentativa $attempt de $maxRetries');

          ftp = FTPConnect(
            config.host,
            port: config.port,
            user: config.username,
            pass: config.password,
            timeout: AppConstants.ftpTimeout.inSeconds,
            securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
            showLog: true,
          );

          final connected = await ftp.connect();
          if (!connected) {
            throw Exception('Falha ao conectar ao servidor FTP');
          }

          try {
            await ftp.sendCustomCommand('TYPE I');
          } on Object catch (e) {
            LoggerService.warning('Não foi possível setar TYPE I (Binary): $e');
          }

          if (config.remotePath.isNotEmpty && config.remotePath != '/') {
            await _createRemoteDirectories(ftp, config.remotePath);
            await ftp.changeDirectory(config.remotePath);
          }

          final uploaded = await ftp.uploadFile(
            sourceFile,
            sRemoteName: fileName,
            onProgress: (double progress, int sent, int total) {
              if (onProgress != null) {
                onProgress(progress);
              }
            },
          );

          if (!uploaded) {
            throw Exception('Falha no upload do arquivo (retorno falso)');
          }

          await Future.delayed(const Duration(seconds: 2));
          final remoteSize = await ftp.sizeFile(fileName);
          if (remoteSize != -1 && remoteSize != fileSize) {
            try {
              await ftp.deleteFile(fileName);
            } on Object catch (e) {
              LoggerService.warning(
                'Não foi possível remover arquivo corrompido: $e',
              );
            }

            throw Exception(
              'Arquivo corrompido no destino. '
              'Tamanho local: $fileSize, Remoto: $remoteSize',
            );
          }

          await ftp.disconnect();
          ftp = null;

          stopwatch.stop();

          final remotePath = p.posix.join(
            config.remotePath == '/' ? '' : config.remotePath,
            fileName,
          );
          LoggerService.info('Upload FTP concluído: $remotePath');

          return rd.Success(
            FtpUploadResult(
              remotePath: remotePath,
              fileSize: fileSize,
              duration: stopwatch.elapsed,
            ),
          );
        } on Object catch (e) {
          if (ftp != null) {
            try {
              await ftp.disconnect();
            } on Object catch (disconnectError) {
              LoggerService.debug(
                'Erro ao desconectar FTP após falha: $disconnectError',
              );
            }
          }

          lastError = e is Exception ? e : Exception(e.toString());
          final errorMessage = 'Tentativa $attempt de $maxRetries falhou: $e';
          failedAttempts.add(errorMessage);
          LoggerService.warning(errorMessage);

          if (attempt < maxRetries) {
            await Future.delayed(AppConstants.retryDelay);
          }
        }
      }

      stopwatch.stop();
      final baseMessage = _getFtpErrorMessage(lastError, config.host);
      final attemptsMessage = failedAttempts.isNotEmpty
          ? '\n\nTentativas realizadas:\n${failedAttempts.join('\n')}'
          : '';
      return rd.Failure(
        FtpFailure(
          message: '$baseMessage$attemptsMessage',
          originalError: lastError,
        ),
      );
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro no upload FTP', e, stackTrace);
      return rd.Failure(
        FtpFailure(
          message: _getFtpErrorMessage(e, config.host),
          originalError: e,
        ),
      );
    }
  }

  String _getFtpErrorMessage(dynamic e, String host) {
    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('connection refused') || errorStr.contains('host')) {
      return 'Não foi possível conectar ao servidor FTP: $host\n'
          'Verifique se o servidor está online e acessível.';
    } else if (errorStr.contains('login') ||
        errorStr.contains('530') ||
        errorStr.contains('auth')) {
      return 'Falha na autenticação FTP\n'
          'Verifique usuário e senha.';
    } else if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao conectar ao FTP: $host\n'
          'Verifique sua conexão de rede.';
    } else if (errorStr.contains('permission') || errorStr.contains('550')) {
      return 'Sem permissão para escrever no servidor FTP\n'
          'Verifique as permissões do diretório remoto.';
    } else if (errorStr.contains('disk') ||
        errorStr.contains('space') ||
        errorStr.contains('452')) {
      return 'Servidor FTP sem espaço em disco.';
    }

    return 'Erro no upload FTP após várias tentativas.\n'
        'Servidor: $host\nDetalhes: $e';
  }

  Future<void> _createRemoteDirectories(FTPConnect ftp, String path) async {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    var currentPath = '';

    for (final part in parts) {
      currentPath = '$currentPath/$part';
      await _createRemoteDirectory(ftp, part);
      await ftp.changeDirectory(part);
    }

    await ftp.changeDirectory('/');
  }

  Future<void> _createRemoteDirectory(FTPConnect ftp, String dirName) async {
    try {
      await ftp.makeDirectory(dirName);
    } on Object catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('exists') ||
          msg.contains('550') ||
          msg.contains('already')) {
        LoggerService.debug('Diretório já existe: $dirName');
        return;
      }
      rethrow;
    }
  }

  @override
  Future<rd.Result<bool>> testConnection(FtpDestinationConfig config) async {
    try {
      final ftp = FTPConnect(
        config.host,
        port: config.port,
        user: config.username,
        pass: config.password,
        securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
      );

      final connected = await ftp.connect();
      if (connected) {
        await ftp.disconnect();
        return const rd.Success(true);
      }
      return const rd.Success(false);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao testar conexão FTP',
        e,
        stackTrace,
      );
      return rd.Failure(FtpFailure(message: 'Erro ao testar conexão FTP: $e'));
    }
  }

  @override
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
        timeout: AppConstants.ftpTimeout.inSeconds,
        securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
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
