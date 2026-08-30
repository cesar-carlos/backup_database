import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:backup_database/core/errors/failure_codes.dart';
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
      ftp = FTPConnect(
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
      ftpConnected = connected;
      if (!connected) {
        throw Exception('Falha ao conectar ao servidor FTP');
      }
      cancellationWatcher = _uploader.startCancellationWatcher(
        ftp: ftp,
        isCancelled: isCancelled,
        context: ctx,
      );

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
        await ftp.changeDirectory(config.remotePath);
      }

      final alreadyUploaded = await _uploader.isRemoteFileAlreadyComplete(
        ftp: ftp,
        remoteFileName: fileName,
        expectedSize: fileSize,
        localSha256: sha256Hash,
        enableStrongIntegrityValidation: config.enableStrongIntegrityValidation,
        enableReadBackValidation: config.enableReadBackValidation,
      );
      if (alreadyUploaded) {
        cancellationWatcher?.cancel();
        await ftp.disconnect();
        ftpConnected = false;
        ftp = null;
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

      final validationResult = await _integrityVerifier.validatePartSize(
        ftp,
        remotePartName,
        fileSize,
      );

      if (!validationResult.isValid) {
        await _uploader.safeDeletePart(ftp, remotePartName);
        return rd.Failure(
          FtpFailure(
            message: validationResult.errorMessage!,
            code: FailureCodes.ftpIntegrityValidationFailed,
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

      final finalIntegrityResult = await _integrityVerifier
          .validateFinalIntegrity(
            ftp: ftp,
            remoteFileName: fileName,
            expectedSize: fileSize,
            localSha256: sha256Hash,
            enableStrongIntegrityValidation:
                config.enableStrongIntegrityValidation,
            enableReadBackValidation: config.enableReadBackValidation,
          );
      if (!finalIntegrityResult.isValid) {
        await _uploader.safeDeletePart(ftp, fileName);
        return rd.Failure(
          FtpFailure(
            message: finalIntegrityResult.errorMessage!,
            code: finalIntegrityResult.failureCode,
            originalError: finalIntegrityResult.originalError,
          ),
        );
      }

      if (sha256Hash != null) {
        await _integrityVerifier.uploadSidecar(ftp, fileName, sha256Hash);
      }

      cancellationWatcher?.cancel();
      await ftp.disconnect();
      ftpConnected = false;
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
    } on FtpResumeNotSupportedPolicyException catch (e) {
      cancellationWatcher?.cancel();
      if (ftp != null && ftpConnected) {
        try {
          await ftp.disconnect();
        } on Object catch (e, st) {
          LoggerService.debug(
            'FTP disconnect after resume policy failure: $e',
            e,
            st,
          );
        }
      }
      return rd.Failure(e.failure);
    } on UploadCancelledException {
      cancellationWatcher?.cancel();
      if (ftp != null && ftpConnected) {
        if (!config.keepPartOnCancel) {
          try {
            await _uploader.safeDeletePart(ftp, remotePartName);
          } on Object catch (e, st) {
            LoggerService.debug(
              'FTP delete part after cancel: $e',
              e,
              st,
            );
          }
        }
        try {
          await ftp.disconnect();
          ftpConnected = false;
        } on Object catch (disconnectError) {
          LoggerService.debug(
            'Erro ao desconectar FTP após cancelamento: $disconnectError',
          );
        }
      }
      LoggerService.info('$ctx Upload FTP cancelado pelo usuário');
      return UploadCancellation.cancelledResult();
    } on Object catch (e, stackTrace) {
      cancellationWatcher?.cancel();
      if (ftp != null && ftpConnected) {
        try {
          await ftp.disconnect();
          ftpConnected = false;
        } on Object catch (disconnectError) {
          LoggerService.debug(
            'Erro ao desconectar FTP após falha: $disconnectError',
          );
        }
      }

      stopwatch.stop();
      final lastError = e is Exception ? e : Exception(e.toString());
      LoggerService.warning(
        '$ctx Upload FTP falhou: $e',
        lastError,
        stackTrace,
      );
      return rd.Failure(
        FtpFailure(
          message: getFtpErrorMessage(e, config.host),
          originalError: e,
        ),
      );
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
