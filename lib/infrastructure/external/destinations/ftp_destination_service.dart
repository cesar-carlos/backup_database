import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure.dart' hide FtpFailure;
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/ftp_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp_upload_offset_decision.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class FtpDestinationService implements IFtpService {
  @override
  Future<rd.Result<FtpUploadResult>> upload({
    required String sourceFilePath,
    required FtpDestinationConfig config,
    String? customFileName,
    int maxRetries = 1,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
    String? runId,
    String? destinationId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final ctx = _buildLogContext(runId: runId, destinationId: destinationId);

    try {
      LoggerService.info('$ctx Enviando para FTP: ${config.host}');

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

      final hashStopwatch = Stopwatch()..start();
      LoggerService.debug('Calculando SHA-256 do arquivo local...');
      final sha256Hash = await _computeSha256Streaming(sourceFile);
      hashStopwatch.stop();
      if (sha256Hash != null) {
        LoggerService.debug(
          'SHA-256 calculado em ${hashStopwatch.elapsedMilliseconds}ms '
          '(${_formatFileSize(fileSize)})',
        );
      }

      FTPConnect? ftp;
      try {
        ftp = FTPConnect(
          config.host,
          port: config.port,
          user: config.username,
          pass: config.password,
          timeout: config.effectiveUploadTimeoutSeconds,
          securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
          showLog: config.enableVerboseLog || kDebugMode,
        );

        final connected = await ftp.connect();
        if (!connected) {
          throw Exception('Falha ao conectar ao servidor FTP');
        }

        final supportsRestStream = await _checkRestStreamSupport(ftp);
        switch (supportsRestStream) {
          case true:
            LoggerService.debug('Upload FTP: servidor suporta REST STREAM');
          case false:
            LoggerService.debug(
              'Upload FTP: fallback para upload completo (REST STREAM não suportado)',
            );
          case null:
            break;
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

        const partSuffix = '.part';
        final remotePartName = '$fileName$partSuffix';

        final uploadResult = await _performUploadWithResume(
          ftp: ftp,
          sourceFile: sourceFile,
          fileSize: fileSize,
          remotePartName: remotePartName,
          supportsRestStream: supportsRestStream ?? false,
          enableResumeFromConfig: config.enableResume,
          whenResumeNotSupportedFail:
              config.whenResumeNotSupported == FtpWhenResumeNotSupported.fail,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );

        if (!uploadResult.uploaded) {
          await _safeDeletePart(ftp, remotePartName);
          throw Exception('Falha no upload do arquivo (retorno falso)');
        }

        final validationResult = await _validatePartSize(
          ftp,
          remotePartName,
          fileSize,
        );

        if (!validationResult.isValid) {
          await _safeDeletePart(ftp, remotePartName);
          return rd.Failure(
            FtpFailure(
              message: validationResult.errorMessage!,
              code: FailureCodes.ftpIntegrityValidationFailed,
              originalError: validationResult.originalError,
            ),
          );
        }

        final renamed = await ftp.rename(remotePartName, fileName);
        if (!renamed) {
          await _safeDeletePart(ftp, remotePartName);
          throw Exception(
            'Falha ao renomear arquivo temporário para nome final. '
            'Verifique permissões no servidor FTP.',
          );
        }

        if (sha256Hash != null) {
          await _uploadSidecar(ftp, fileName, sha256Hash);
        }

        await ftp.disconnect();
        ftp = null;

        stopwatch.stop();

        final remotePath = p.posix.join(
          config.remotePath == '/' ? '' : config.remotePath,
          fileName,
        );
        final hashInfo = sha256Hash != null
            ? ' (SHA-256: $sha256Hash, hash ${hashStopwatch.elapsedMilliseconds}ms)'
            : '';
        LoggerService.info('$ctx Upload FTP concluído: $remotePath$hashInfo');

        return rd.Success(
          FtpUploadResult(
            remotePath: remotePath,
            fileSize: fileSize,
            duration: stopwatch.elapsed,
            sha256: sha256Hash,
            hashDurationMs: sha256Hash != null
                ? hashStopwatch.elapsedMilliseconds
                : null,
          ),
        );
      } on _ResumeNotSupportedPolicyException catch (e) {
        if (ftp != null) {
          try {
            await ftp.disconnect();
          } on Object catch (_) {}
        }
        return rd.Failure(e.failure);
      } on _UploadCancelledException {
        if (ftp != null) {
          if (!config.keepPartOnCancel) {
            try {
              await _safeDeletePart(ftp, '$fileName.part');
            } on Object catch (_) {}
          }
          try {
            await ftp.disconnect();
          } on Object catch (disconnectError) {
            LoggerService.debug(
              'Erro ao desconectar FTP após cancelamento: $disconnectError',
            );
          }
        }
        LoggerService.info('$ctx Upload FTP cancelado pelo usuário');
        return const rd.Failure(
          BackupFailure(
            message: 'Upload cancelado pelo usuário.',
            code: FailureCodes.uploadCancelled,
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

        stopwatch.stop();
        final lastError = e is Exception ? e : Exception(e.toString());
        LoggerService.warning('$ctx Upload FTP falhou: $e', lastError);
        return rd.Failure(
          FtpFailure(
            message: _getFtpErrorMessage(lastError, config.host),
            originalError: lastError,
          ),
        );
      }
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('$ctx Erro no upload FTP', e, stackTrace);
      return rd.Failure(
        FtpFailure(
          message: _getFtpErrorMessage(e, config.host),
          originalError: e,
        ),
      );
    }
  }

  Future<_UploadResult> _performUploadWithResume({
    required FTPConnect ftp,
    required File sourceFile,
    required int fileSize,
    required String remotePartName,
    required bool supportsRestStream,
    required bool enableResumeFromConfig,
    bool whenResumeNotSupportedFail = false,
    UploadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    void ftpProgressAdapter(
      double progressPercent,
      int sent,
      int total, {
      String? stepOverride,
    }) {
      if (isCancelled != null && isCancelled()) {
        throw _UploadCancelledException();
      }
      onProgress?.call(progressPercent / 100, stepOverride);
    }

    var remoteSize = await ftp.sizeFile(remotePartName);
    if (remoteSize == -1) {
      remoteSize = 0;
    }

    const globalResumeEnabled = AppConstants.ftpResumableUpload;
    final resumeEnabled = globalResumeEnabled && enableResumeFromConfig;
    final effectiveSupportsRest = supportsRestStream && resumeEnabled;
    final decision = computeFtpUploadOffsetDecision(
      remoteSize,
      fileSize,
      effectiveSupportsRest,
    );

    switch (decision) {
      case FtpUploadSkipAndValidate():
        LoggerService.debug(
          'Parcial remoto já completo ($remoteSize bytes); '
          'validando sem reenviar',
        );
        return const _UploadResult(uploaded: true, resumed: false);

      case FtpUploadResume(:final offset):
        LoggerService.info(
          'Retomando upload de $remotePartName a partir do byte $offset',
        );
        final uploaded = await ftp.uploadFileWithResume(
          sourceFile,
          offset: offset,
          sRemoteName: remotePartName,
          onProgress: (p, s, t) => ftpProgressAdapter(
            p,
            s,
            t,
            stepOverride: 'Retomando de ${p.toInt()}%',
          ),
        );
        return _UploadResult(uploaded: uploaded, resumed: true);

      case FtpUploadFullUpload():
        if (remoteSize > fileSize) {
          LoggerService.debug(
            'Parcial remoto ($remoteSize) maior que local ($fileSize); '
            'removendo e reiniciando upload',
          );
          await _safeDeletePart(ftp, remotePartName);
        } else if (remoteSize > 0 && !effectiveSupportsRest) {
          if (whenResumeNotSupportedFail) {
            throw _ResumeNotSupportedPolicyException(
              FtpFailure(
                message:
                    'Servidor não suporta retomada (REST STREAM) e existe '
                    'parcial remoto ($remoteSize bytes). '
                    'Configure política "fallback" ou use servidor compatível.',
                code: FailureCodes.ftpIntegrityValidationFailed,
              ),
            );
          }
          final reason = !enableResumeFromConfig
              ? 'retomada desabilitada no destino'
              : !globalResumeEnabled
                  ? 'retomada desabilitada por feature flag'
                  : 'servidor não suporta REST STREAM';
          LoggerService.debug(
            'Parcial remoto existe ($remoteSize bytes) mas $reason; '
            'reiniciando upload completo',
          );
          await _safeDeletePart(ftp, remotePartName);
        }
        final uploaded = await ftp.uploadFile(
          sourceFile,
          sRemoteName: remotePartName,
          onProgress: ftpProgressAdapter,
        );
        return _UploadResult(uploaded: uploaded, resumed: false);
    }
  }

  static String _buildLogContext({String? runId, String? destinationId}) {
    final parts = <String>[];
    if (runId != null && runId.isNotEmpty) parts.add('runId=$runId');
    if (destinationId != null && destinationId.isNotEmpty) {
      parts.add('destinationId=$destinationId');
    }
    if (parts.isEmpty) return '';
    return '${parts.map((p) => '[$p]').join()} ';
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  Future<String?> _computeSha256Streaming(File file) async {
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString();
    } on Object catch (e) {
      LoggerService.warning(
        'Não foi possível calcular SHA-256: $e. Sidecar não será enviado.',
      );
      return null;
    }
  }

  Future<void> _uploadSidecar(
    FTPConnect ftp,
    String fileName,
    String sha256Hash,
  ) async {
    const sidecarSuffix = '.sha256';
    final sidecarName = '$fileName$sidecarSuffix';
    final content = '$sha256Hash  $fileName';

    final tempFile = File(
      p.join(
        Directory.systemTemp.path,
        '${DateTime.now().millisecondsSinceEpoch}_$sidecarName',
      ),
    );
    try {
      await tempFile.writeAsString(content);
      final uploaded = await ftp.uploadFile(
        tempFile,
        sRemoteName: sidecarName,
      );
      if (!uploaded) {
        LoggerService.warning(
          'Falha ao enviar sidecar .sha256; hash registrado no log.',
        );
      }
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao enviar sidecar .sha256: $e. Hash registrado no log.',
      );
    } finally {
      try {
        await tempFile.delete();
      } on Object catch (_) {}
    }
  }

  Future<void> _safeDeletePart(FTPConnect ftp, String remotePartName) async {
    try {
      await ftp.deleteFile(remotePartName);
    } on Object catch (e) {
      LoggerService.warning(
        'Não foi possível remover arquivo temporário: $e',
      );
    }
  }

  static const _sizeValidationRetries = 3;
  static const _sizeValidationRetryDelay = Duration(milliseconds: 500);

  Future<_SizeValidationResult> _validatePartSize(
    FTPConnect ftp,
    String remotePartName,
    int expectedSize,
  ) async {
    for (var i = 0; i < _sizeValidationRetries; i++) {
      final remoteSize = await ftp.sizeFile(remotePartName);
      if (remoteSize == -1) {
        if (i < _sizeValidationRetries - 1) {
          await Future.delayed(_sizeValidationRetryDelay);
          continue;
        }
        return _SizeValidationResult(
          isValid: false,
          errorMessage:
              'Não foi possível validar tamanho do arquivo no destino '
              '(comando SIZE não suportado ou falhou). '
              'Integridade não confirmada.',
          originalError: Exception(
            'SIZE retornou -1 após $_sizeValidationRetries tentativas',
          ),
        );
      }
      if (remoteSize != expectedSize) {
        return _SizeValidationResult(
          isValid: false,
          errorMessage:
              'Arquivo corrompido no destino. '
              'Tamanho local: $expectedSize, Remoto: $remoteSize',
          originalError: Exception(
            'Divergência de tamanho: local=$expectedSize remoto=$remoteSize',
          ),
        );
      }
      return const _SizeValidationResult(isValid: true);
    }
    return const _SizeValidationResult(isValid: true);
  }

  String _getFtpErrorMessage(dynamic e, String host) {
    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('connection refused') ||
        errorStr.contains('host') ||
        errorStr.contains('socket')) {
      return 'Erro de conexão: não foi possível conectar ao servidor FTP: $host\n'
          'Verifique se o servidor está online e acessível.';
    }
    if (errorStr.contains('login') ||
        errorStr.contains('530') ||
        errorStr.contains('auth')) {
      return 'Erro de autenticação FTP\n'
          'Verifique usuário e senha.';
    }
    if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao conectar ao FTP: $host\n'
          'Verifique sua conexão de rede.';
    }
    if (errorStr.contains('permission') ||
        errorStr.contains('550') ||
        errorStr.contains('rename') ||
        errorStr.contains('rnfr') ||
        errorStr.contains('rnto')) {
      return 'Erro de permissão: sem permissão para escrever ou renomear no servidor FTP\n'
          'Verifique as permissões do diretório remoto.';
    }
    if (errorStr.contains('corrompido') ||
        errorStr.contains('integridade') ||
        errorStr.contains('tamanho') ||
        errorStr.contains('size')) {
      return 'Erro de integridade: arquivo no destino não confere com o original.\n'
          'Detalhes: $e';
    }
    if (errorStr.contains('disk') ||
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

  Future<bool?> _checkRestStreamSupport(FTPConnect ftp) async {
    try {
      final reply = await ftp.sendCustomCommand('FEAT');
      final success = reply.isSuccessCode();
      if (!success) return null;
      final msg = reply.message.toUpperCase();
      if (msg.contains('REST STREAM')) return true;
      if (msg.contains('REST')) {
        LoggerService.debug(
          'Servidor FTP reporta REST mas não REST STREAM; '
          'retomada por offset pode não funcionar',
        );
        return false;
      }
      return false;
    } on Object catch (e) {
      LoggerService.debug('FEAT não suportado ou falhou: $e');
      return null;
    }
  }

  @override
  Future<rd.Result<FtpConnectionTestResult>> testConnection(
    FtpDestinationConfig config,
  ) async {
    try {
      final ftp = FTPConnect(
        config.host,
        port: config.port,
        user: config.username,
        pass: config.password,
        timeout: config.effectiveConnectionTimeoutSeconds,
        securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
        showLog: config.enableVerboseLog || kDebugMode,
      );

      final connected = await ftp.connect();
      if (!connected) {
        return const rd.Success(
          FtpConnectionTestResult(connected: false),
        );
      }

      try {
        await ftp.sendCustomCommand('TYPE I');
      } on Object catch (_) {}

      var canWrite = true;
      var canRename = true;

      if (config.remotePath.isNotEmpty && config.remotePath != '/') {
        await _createRemoteDirectories(ftp, config.remotePath);
        await ftp.changeDirectory(config.remotePath);
      }

      final testFileName =
          '_test_conn_${DateTime.now().millisecondsSinceEpoch}.tmp';
      final testFileRenamed = '$testFileName.ok';

      final tempFile = File(
        p.join(
          Directory.systemTemp.path,
          '${DateTime.now().millisecondsSinceEpoch}_ftp_test.tmp',
        ),
      );
      try {
        await tempFile.writeAsString('test');
        final uploaded = await ftp.uploadFile(
          tempFile,
          sRemoteName: testFileName,
        );
        if (!uploaded) {
          canWrite = false;
          LoggerService.warning(
            'Teste FTP: falha ao enviar arquivo de teste (permissão de escrita)',
          );
        } else {
          final renamed = await ftp.rename(testFileName, testFileRenamed);
          if (!renamed) {
            canRename = false;
            LoggerService.warning(
              'Teste FTP: falha ao renomear arquivo (RNFR/RNTO)',
            );
            await _safeDeletePart(ftp, testFileName);
          } else {
            await _safeDeletePart(ftp, testFileRenamed);
          }
        }
      } finally {
        try {
          await tempFile.delete();
        } on Object catch (_) {}
      }

      final supportsRestStream = await _checkRestStreamSupport(ftp);
      await ftp.disconnect();

      switch (supportsRestStream) {
        case true:
          LoggerService.info(
            'Teste FTP: conexão OK; servidor suporta REST STREAM (retomada)',
          );
        case false:
          LoggerService.info(
            'Teste FTP: conexão OK; servidor não suporta REST STREAM '
            '(retomada por offset indisponível)',
          );
        case null:
          LoggerService.info(
            'Teste FTP: conexão OK; capacidade REST STREAM não determinada',
          );
      }

      return rd.Success(
        FtpConnectionTestResult(
          connected: true,
          supportsRestStream: supportsRestStream,
          canWrite: canWrite,
          canRename: canRename,
        ),
      );
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
        timeout: config.effectiveUploadTimeoutSeconds,
        securityType: config.useFtps ? SecurityType.ftps : SecurityType.ftp,
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

class _UploadResult {
  const _UploadResult({required this.uploaded, required this.resumed});
  final bool uploaded;
  final bool resumed;
}

class _SizeValidationResult {
  const _SizeValidationResult({
    required this.isValid,
    this.errorMessage,
    this.originalError,
  });
  final bool isValid;
  final String? errorMessage;
  final Object? originalError;
}

class _UploadCancelledException implements Exception {
  _UploadCancelledException();
}

class _ResumeNotSupportedPolicyException implements Exception {
  _ResumeNotSupportedPolicyException(this.failure);
  final FtpFailure failure;
}
