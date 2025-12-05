import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:path/path.dart' as p;

import '../../../core/errors/failure.dart' hide FtpFailure;
import '../../../core/errors/ftp_failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../core/constants/app_constants.dart';

class FtpDestinationConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;
  final bool useFtps;
  final int retentionDays;

  const FtpDestinationConfig({
    required this.host,
    this.port = 21,
    required this.username,
    required this.password,
    this.remotePath = '/',
    this.useFtps = false,
    this.retentionDays = 30,
  });
}

class FtpUploadResult {
  final String remotePath;
  final int fileSize;
  final Duration duration;

  const FtpUploadResult({
    required this.remotePath,
    required this.fileSize,
    required this.duration,
  });
}

class FtpDestinationService {
  Future<rd.Result<FtpUploadResult>> upload({
    required String sourceFilePath,
    required FtpDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
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

      // Tentar upload com retry
      Exception? lastError;
      final List<String> failedAttempts = [];
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          LoggerService.debug('Tentativa $attempt de $maxRetries');

          final ftp = FTPConnect(
            config.host,
            port: config.port,
            user: config.username,
            pass: config.password,
            timeout: AppConstants.ftpTimeout.inSeconds,
            securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
          );

          // Conectar
          final connected = await ftp.connect();
          if (!connected) {
            throw Exception('Falha ao conectar ao servidor FTP');
          }

          // Navegar para diretório remoto
          if (config.remotePath.isNotEmpty && config.remotePath != '/') {
            await _createRemoteDirectories(ftp, config.remotePath);
            await ftp.changeDirectory(config.remotePath);
          }

          // Upload diretamente na pasta indicada
          final uploaded = await ftp.uploadFile(
            sourceFile,
            sRemoteName: fileName,
          );
          if (!uploaded) {
            throw Exception('Falha no upload do arquivo');
          }

          // Desconectar
          await ftp.disconnect();

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
        } catch (e) {
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
    } catch (e, stackTrace) {
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
    String currentPath = '';

    for (final part in parts) {
      currentPath = '$currentPath/$part';
      await _createRemoteDirectory(ftp, part);
      try {
        await ftp.changeDirectory(part);
      } catch (e) {
        // Ignorar erro se não conseguir mudar de diretório
      }
    }

    // Voltar para raiz
    try {
      await ftp.changeDirectory('/');
    } catch (e) {
      // Ignorar erro
    }
  }

  Future<void> _createRemoteDirectory(FTPConnect ftp, String dirName) async {
    try {
      await ftp.makeDirectory(dirName);
    } catch (e) {
      // Diretório pode já existir, ignorar erro
    }
  }

  Future<rd.Result<bool>> testConnection(FtpDestinationConfig config) async {
    try {
      final ftp = FTPConnect(
        config.host,
        port: config.port,
        user: config.username,
        pass: config.password,
        timeout: 30,
        securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
      );

      final connected = await ftp.connect();
      if (connected) {
        await ftp.disconnect();
        return const rd.Success(true);
      }
      return const rd.Success(false);
    } catch (e) {
      return rd.Failure(FtpFailure(message: 'Erro ao testar conexão FTP: $e'));
    }
  }

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
        } catch (e) {
          // Diretório não existe, sem backups para limpar
          await ftp.disconnect();
          return const rd.Success(0);
        }
      }

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      int deletedCount = 0;
      final items = await ftp.listDirectoryContent();

      for (final item in items) {
        if (item.type == FTPEntryType.file) {
          // Tentar extrair data do nome do arquivo (formato: NOME_YYYY-MM-DDTHH-MM-SS.bak)
          try {
            final fileName = item.name;
            // Procurar padrão de data no nome do arquivo
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
          } catch (e) {
            // Se não conseguir extrair data do nome, ignorar arquivo
            LoggerService.debug(
              'Não foi possível extrair data do arquivo ${item.name}: $e',
            );
          }
        }
      }

      await ftp.disconnect();
      LoggerService.info('$deletedCount arquivos antigos removidos do FTP');
      return rd.Success(deletedCount);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao limpar backups FTP', e, stackTrace);
      return rd.Failure(
        FtpFailure(message: 'Erro ao limpar backups FTP: $e', originalError: e),
      );
    }
  }
}
