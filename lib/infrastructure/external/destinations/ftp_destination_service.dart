import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:backup_database/core/errors/ftp_failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_connection_tester.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_integrity_verifier.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_retention.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_uploader.dart';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class FtpDestinationService implements IFtpService {
  FtpDestinationService({
    FtpUploader? uploader,
    FtpIntegrityVerifier? integrityVerifier,
    FtpRetention? retention,
    FtpConnectionTester? connectionTester,
    this._clientFactory,
  }) : _integrityVerifier = integrityVerifier ?? FtpIntegrityVerifier(),
       _retention = retention ?? FtpRetention() {
    _uploader = uploader ?? FtpUploader(integrityVerifier: _integrityVerifier);
    _connectionTester =
        connectionTester ?? FtpConnectionTester(uploader: _uploader);
  }

  late final FtpUploader _uploader;
  final FtpIntegrityVerifier _integrityVerifier;
  final FtpRetention _retention;
  late final FtpConnectionTester _connectionTester;
  final FTPConnect Function(FtpDestinationConfig)? _clientFactory;

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

    LoggerService.info('$ctx Enviando para FTP: ${config.host}');
    if (isCancelled?.call() ?? false) {
      return UploadCancellation.cancelledResult();
    }

    final missingSource = await BackupArtifactUtils.missingSourceFileFailure(
      sourceFilePath,
    );
    if (missingSource != null) return rd.Failure(missingSource);
    final sourceFile = File(sourceFilePath);

    final fileSize = await sourceFile.length();
    final fileName = customFileName ?? p.basename(sourceFilePath);
    final remotePartName = buildRemotePartName(
      finalFileName: fileName,
      runId: runId,
      destinationId: destinationId,
    );

    final hashStopwatch = Stopwatch()..start();
    LoggerService.debug('Calculando SHA-256 do arquivo local...');
    final sha256Hash = await _integrityVerifier.computeSha256Streaming(
      sourceFile,
    );
    hashStopwatch.stop();
    if (sha256Hash != null) {
      LoggerService.debug(
        'SHA-256 calculado em ${hashStopwatch.elapsedMilliseconds}ms '
        '(${ByteFormat.format(fileSize)})',
      );
    }

    FTPConnect? ftp;
    var ftpConnected = false;
    Timer? cancellationWatcher;
    try {
      UploadCancellation.throwIfCancelled(isCancelled);
      ftp = _createClient(config);
      cancellationWatcher = _uploader.startCancellationWatcher(
        ftp: ftp,
        isCancelled: isCancelled,
        context: ctx,
      );
      ftpConnected = await ftp.connect();
      UploadCancellation.throwIfCancelled(isCancelled);
      if (!ftpConnected) throw Exception('Falha ao conectar ao servidor FTP');
      final supportsRestStream = await _uploader.checkRestStreamSupport(ftp);
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

      await _uploader.ensureBinaryTransferType(ftp);

      if (config.remotePath.isNotEmpty && config.remotePath != '/') {
        await _uploader.createRemoteDirectories(ftp, config.remotePath);
        if (!await ftp.changeDirectory(config.remotePath)) {
          throw Exception(
            'Sem permissão para acessar diretório FTP configurado',
          );
        }
      }

      final alreadyUploaded = await _uploader.isRemoteFileAlreadyComplete(
        ftp: ftp,
        remoteFileName: fileName,
        expectedSize: fileSize,
        localSha256: sha256Hash,
        enableStrongIntegrityValidation: config.enableStrongIntegrityValidation,
        enableReadBackValidation: config.enableReadBackValidation,
      );
      UploadCancellation.throwIfCancelled(isCancelled);
      if (alreadyUploaded) {
        cancellationWatcher?.cancel();
        await ftp.disconnect();
        ftpConnected = false;
        ftp = null;
        UploadCancellation.throwIfCancelled(isCancelled);
        stopwatch.stop();

        final remotePath = p.posix.join(
          config.remotePath == '/' ? '' : config.remotePath,
          fileName,
        );
        LoggerService.info(
          '$ctx Upload FTP concluído por idempotência: '
          '$remotePath (arquivo já existente no destino)',
        );

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
      }

      final uploadResult = await _uploader.performUploadWithResume(
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
        await _uploader.safeDeletePart(ftp, remotePartName);
        throw Exception('Falha no upload do arquivo (retorno falso)');
      }
      UploadCancellation.throwIfCancelled(isCancelled);

      final validationResult = await _integrityVerifier.validateFinalIntegrity(
        ftp: ftp,
        remoteFileName: remotePartName,
        expectedSize: fileSize,
        localSha256: sha256Hash,
        enableStrongIntegrityValidation:
            uploadResult.resumed || config.enableStrongIntegrityValidation,
        enableReadBackValidation:
            uploadResult.resumed || config.enableReadBackValidation,
      );
      UploadCancellation.throwIfCancelled(isCancelled);
      if (!validationResult.isValid) {
        await _uploader.safeDeletePart(ftp, remotePartName);
        return rd.Failure(
          FtpFailure(
            message: validationResult.errorMessage!,
            code: validationResult.failureCode,
            originalError: validationResult.originalError,
          ),
        );
      }
      UploadCancellation.throwIfCancelled(isCancelled);

      final renamed = await ftp.rename(remotePartName, fileName);
      if (!renamed) {
        await _uploader.safeDeletePart(ftp, remotePartName);
        throw Exception(
          'Falha ao renomear arquivo temporário para nome final. '
          'Verifique permissões no servidor FTP.',
        );
      }

      UploadCancellation.throwIfCancelled(isCancelled);

      if (sha256Hash != null) {
        await _integrityVerifier.uploadSidecar(ftp, fileName, sha256Hash);
      }

      cancellationWatcher?.cancel();
      await ftp.disconnect();
      ftpConnected = false;
      ftp = null;
      UploadCancellation.throwIfCancelled(isCancelled);

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
    } on Object catch (e, stackTrace) {
      cancellationWatcher?.cancel();
      ftp?.abort();
      ftpConnected = false;
      if (e is UploadCancelledException || (isCancelled?.call() ?? false)) {
        if (!config.keepPartOnCancel) {
          await _deleteCancelledPart(config, remotePartName);
        }
        LoggerService.info('$ctx Upload FTP cancelado pelo usuário');
        return UploadCancellation.cancelledResult();
      }
      if (e is FtpResumeNotSupportedPolicyException) {
        return rd.Failure(e.failure);
      }
      LoggerService.warning('$ctx Upload FTP falhou: $e', e, stackTrace);
      return rd.Failure(
        FtpFailure(
          message: getFtpErrorMessage(e, config.host),
          originalError: e,
        ),
      );
    } finally {
      cancellationWatcher?.cancel();
      if (ftp != null && ftpConnected) {
        try {
          await ftp.disconnect();
        } on Object catch (e) {
          LoggerService.debug('Erro ao encerrar conexão FTP: $e');
        }
      }
    }
  }

  FTPConnect _createClient(FtpDestinationConfig config) =>
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

  Future<void> _deleteCancelledPart(
    FtpDestinationConfig config,
    String name,
  ) async {
    // Never issue DELE on the interrupted control channel: its replies may
    // still belong to STOR/RETR. Cleanup needs a separate session.
    final cleanup = _createClient(config);
    try {
      await (() async {
        if (!await cleanup.connect()) return;
        await cleanup.setTransferType(TransferType.binary);
        if (config.remotePath.isNotEmpty &&
            config.remotePath != '/' &&
            !await cleanup.changeDirectory(config.remotePath)) {
          return;
        }
        if (!await cleanup.deleteFile(name)) {
          LoggerService.warning(
            'FTP: não foi possível remover parcial cancelado: $name',
          );
        }
      })().timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      LoggerService.warning('FTP: limpeza do parcial cancelado falhou: $e');
    } finally {
      cleanup.abort();
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

  /// Gera nome do arquivo temporário remoto `<final>.<token>.part`.
  ///
  /// O token combina `runId` + `destinationId` quando disponíveis. Sem eles,
  /// usa `<ms>_<random>` para evitar a classe de colisão documentada no
  /// helper `DirectoryPermissionCheck` (anti-padrão "timestamp puro" em
  /// `architectural_patterns.mdc` §3b): runs concorrentes que caem no
  /// mesmo millisegundo gerariam o mesmo `.part`.
  @visibleForTesting
  static String buildRemotePartName({
    required String finalFileName,
    String? runId,
    String? destinationId,
  }) {
    final tokenSource = <String>[
      if (runId != null && runId.isNotEmpty) runId,
      if (destinationId != null && destinationId.isNotEmpty) destinationId,
    ].join('_');
    final fallbackToken =
        '${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
    final rawToken = tokenSource.isNotEmpty ? tokenSource : fallbackToken;
    final safeToken = rawToken.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    return '$finalFileName.$safeToken.part';
  }

  static final _random = Random.secure();

  /// 8 hex chars (~32 bits) de entropia para sufixos de nomes temporários.
  static String _randomSuffix() {
    final bytes = List<int>.generate(4, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Mapeia uma exceção do upload para uma mensagem amigável ao usuário.
  ///
  /// Estratégia em duas camadas:
  /// 1. **Tipo específico** (`TimeoutException`, `SocketException`,
  ///    `HandshakeException`/`TlsException`): determinístico.
  /// 2. **Heurística por substring** apenas como fallback para exceções
  ///    genéricas do `ftpconnect` (que joga `Exception('...')` com
  ///    códigos FTP no texto: 530, 550, 452 etc.).
  ///
  /// O heurístico foi reforçado para evitar falsos positivos do padrão
  /// anterior (`errorStr.contains('host')` matcheava qualquer mensagem
  /// com a palavra "host" no meio).
  @visibleForTesting
  static String getFtpErrorMessage(Object e, String host) {
    if (e is TimeoutException) {
      return 'Tempo limite excedido ao conectar ao FTP: $host\n'
          'Verifique sua conexão de rede.';
    }
    if (e is HandshakeException || e is TlsException) {
      return 'Erro de TLS/SSL no FTPS: $host\n'
          'Verifique certificado do servidor ou habilite '
          '"aceitar certificados inválidos" para servidores autoassinados.\n'
          'Detalhes: $e';
    }
    if (e is SocketException) {
      return 'Erro de conexão: não foi possível conectar ao servidor FTP: $host\n'
          'Verifique se o servidor está online e acessível.\n'
          'Detalhes: ${e.message}';
    }

    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('connection refused') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('no route to host') ||
        errorStr.contains('unreachable') ||
        errorStr.contains('hostname')) {
      return 'Erro de conexão: não foi possível conectar ao servidor FTP: $host\n'
          'Verifique se o servidor está online e acessível.';
    }
    if (errorStr.contains('login') ||
        _containsFtpCode(errorStr, 530) ||
        errorStr.contains('auth')) {
      return 'Erro de autenticação FTP\n'
          'Verifique usuário e senha.';
    }
    if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao conectar ao FTP: $host\n'
          'Verifique sua conexão de rede.';
    }
    if (errorStr.contains('disk') ||
        errorStr.contains('no space') ||
        _containsFtpCode(errorStr, 452)) {
      return 'Servidor FTP sem espaço em disco.';
    }
    if (errorStr.contains('permission') ||
        _containsFtpCode(errorStr, 550) ||
        errorStr.contains('rename') ||
        errorStr.contains('rnfr') ||
        errorStr.contains('rnto')) {
      return 'Erro de permissão: sem permissão para escrever ou renomear no servidor FTP\n'
          'Verifique as permissões do diretório remoto.';
    }
    if (errorStr.contains('corrompido') ||
        errorStr.contains('integridade') ||
        errorStr.contains('tamanho')) {
      return 'Erro de integridade: arquivo no destino não confere com o original.\n'
          'Detalhes: $e';
    }
    if (errorStr.contains('não confirmada') ||
        errorStr.contains('inconclusive')) {
      return 'Não foi possível confirmar a integridade no destino FTP.\n'
          'Detalhes: $e';
    }

    return 'Erro no upload FTP após várias tentativas.\n'
        'Servidor: $host\nDetalhes: $e';
  }

  /// Verifica se `text` contém um código FTP de 3 dígitos (e.g. 530, 550)
  /// como token isolado (não como substring acidental dentro de outro
  /// número ou identificador).
  static bool _containsFtpCode(String text, int code) {
    final pattern = RegExp('(?<![0-9])$code(?![0-9])');
    return pattern.hasMatch(text);
  }

  @override
  Future<rd.Result<FtpConnectionTestResult>> testConnection(
    FtpDestinationConfig config,
  ) {
    return _connectionTester.testConnection(config);
  }

  @override
  Future<rd.Result<int>> cleanOldBackups({
    required FtpDestinationConfig config,
  }) {
    return _retention.cleanOldBackups(config: config);
  }
}
