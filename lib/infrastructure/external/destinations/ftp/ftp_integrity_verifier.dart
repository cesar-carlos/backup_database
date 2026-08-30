import 'dart:io';
import 'dart:math';

import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:crypto/crypto.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

class FtpSizeValidationResult {
  const FtpSizeValidationResult({
    required this.isValid,
    this.errorMessage,
    this.failureCode = FailureCodes.ftpIntegrityValidationFailed,
    this.originalError,
  });
  final bool isValid;
  final String? errorMessage;
  final String failureCode;
  final Object? originalError;
}

class FtpIntegrityValidationResult {
  const FtpIntegrityValidationResult({
    required this.isValid,
    this.errorMessage,
    this.failureCode = FailureCodes.ftpIntegrityValidationFailed,
    this.originalError,
  });
  final bool isValid;
  final String? errorMessage;
  final String failureCode;
  final Object? originalError;
}

class FtpIntegrityVerifier {
  static const _sizeValidationRetries = 5;
  static const _sizeValidationRetryDelay = Duration(milliseconds: 800);
  static const _integrityReadBackMaxAttempts = 2;
  static const _integrityReadBackRetryDelay = Duration(seconds: 1);

  static final _random = Random.secure();

  static String _randomSuffix() {
    final bytes = List<int>.generate(4, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _ensureBinaryTransferType(FTPConnect ftp) async {
    try {
      await ftp.setTransferType(TransferType.binary);
    } on Object catch (e) {
      LoggerService.warning(
        'Não foi possível fixar transferência em modo binário (TYPE I): $e',
      );
    }
  }

  Future<String?> computeSha256Streaming(File file) async {
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

  Future<void> uploadSidecar(
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
        '${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}_$sidecarName',
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
      } on Object catch (e, st) {
        LoggerService.debug(
          'FTP sidecar temp delete: $e',
          e,
          st,
        );
      }
    }
  }

  Future<FtpSizeValidationResult> validatePartSize(
    FTPConnect ftp,
    String remotePartName,
    int expectedSize,
  ) async {
    await _ensureBinaryTransferType(ftp);
    int? lastRemoteSize;
    for (var i = 0; i < _sizeValidationRetries; i++) {
      final remoteSize = await ftp.sizeFile(remotePartName);
      if (remoteSize == -1) {
        if (i < _sizeValidationRetries - 1) {
          await Future.delayed(_sizeValidationRetryDelay);
          continue;
        }
        return FtpSizeValidationResult(
          isValid: false,
          errorMessage:
              'Não foi possível validar tamanho do arquivo no destino '
              '(comando SIZE não suportado ou falhou). '
              'Integridade não confirmada após $_sizeValidationRetries '
              'tentativas.',
          failureCode: FailureCodes.ftpIntegrityValidationInconclusive,
          originalError: Exception(
            'SIZE retornou -1 após $_sizeValidationRetries tentativas',
          ),
        );
      }
      if (remoteSize == expectedSize) {
        return const FtpSizeValidationResult(isValid: true);
      }

      lastRemoteSize = remoteSize;
      if (i < _sizeValidationRetries - 1) {
        await Future.delayed(_sizeValidationRetryDelay);
      }
    }
    return FtpSizeValidationResult(
      isValid: false,
      errorMessage:
          'Integridade não confirmada por divergência de tamanho após '
          '$_sizeValidationRetries tentativas. '
          'Tamanho local: $expectedSize, Remoto: $lastRemoteSize',
      originalError: Exception(
        'Divergência de tamanho persistente: '
        'local=$expectedSize remoto=$lastRemoteSize',
      ),
    );
  }

  Future<FtpIntegrityValidationResult> validateFinalIntegrity({
    required FTPConnect ftp,
    required String remoteFileName,
    required int expectedSize,
    required String? localSha256,
    required bool enableStrongIntegrityValidation,
    required bool enableReadBackValidation,
  }) async {
    final finalSizeValidation = await validatePartSize(
      ftp,
      remoteFileName,
      expectedSize,
    );
    if (!finalSizeValidation.isValid) {
      return FtpIntegrityValidationResult(
        isValid: false,
        errorMessage: finalSizeValidation.errorMessage,
        failureCode: finalSizeValidation.failureCode,
        originalError: finalSizeValidation.originalError,
      );
    }

    if (!enableStrongIntegrityValidation) {
      return const FtpIntegrityValidationResult(isValid: true);
    }

    if (localSha256 == null || localSha256.isEmpty) {
      return FtpIntegrityValidationResult(
        isValid: false,
        failureCode: FailureCodes.ftpIntegrityValidationInconclusive,
        errorMessage:
            'Não foi possível calcular SHA-256 local para validar integridade '
            'do arquivo remoto.',
        originalError: Exception('SHA-256 local ausente'),
      );
    }

    final remoteSha256 = await _tryGetRemoteSha256(ftp, remoteFileName);
    if (remoteSha256 != null) {
      if (remoteSha256.toLowerCase() == localSha256.toLowerCase()) {
        LoggerService.info(
          'Integridade FTP validada por HASH remoto (SHA-256) para '
          '$remoteFileName',
        );
        return const FtpIntegrityValidationResult(isValid: true);
      }
      return FtpIntegrityValidationResult(
        isValid: false,
        errorMessage:
            'Falha de integridade no destino FTP: hash remoto difere do local. '
            'SHA local: $localSha256, SHA remoto: $remoteSha256',
        originalError: Exception(
          'Divergência SHA-256: local=$localSha256 remoto=$remoteSha256',
        ),
      );
    }

    if (!enableReadBackValidation) {
      return FtpIntegrityValidationResult(
        isValid: false,
        failureCode: FailureCodes.ftpIntegrityValidationInconclusive,
        errorMessage:
            'Servidor FTP não suportou comando de hash e a validação por '
            'read-back está desabilitada. Integridade não confirmada.',
        originalError: Exception(
          'Sem suporte a hash remoto e read-back desabilitado',
        ),
      );
    }

    return _verifyByReadBack(
      ftp: ftp,
      remoteFileName: remoteFileName,
      localSha256: localSha256,
    );
  }

  Future<String?> _tryGetRemoteSha256(
    FTPConnect ftp,
    String remoteFileName,
  ) async {
    await _ensureBinaryTransferType(ftp);

    // RFC 3659 extension used by many servers.
    try {
      await ftp.sendCustomCommand('OPTS HASH SHA-256');
    } on Object catch (e, st) {
      LoggerService.debug(
        'FTP OPTS HASH not supported or failed: $e',
        e,
        st,
      );
    }

    final commands = <String>[
      'HASH $remoteFileName',
      'XSHA256 $remoteFileName',
      'SITE SHA256 $remoteFileName',
    ];

    for (final command in commands) {
      try {
        final reply = await ftp.sendCustomCommand(command);
        if (!reply.isSuccessCode()) {
          continue;
        }
        final parsed = _extractSha256FromReply(reply.message);
        if (parsed != null) {
          return parsed;
        }
      } on Object catch (e) {
        LoggerService.debug('Comando $command não suportado: $e');
      }
    }

    return null;
  }

  String? _extractSha256FromReply(String replyMessage) {
    final pattern = RegExp('(?<![A-Fa-f0-9])[A-Fa-f0-9]{64}(?![A-Fa-f0-9])');
    final match = pattern.firstMatch(replyMessage);
    return match?.group(0);
  }

  Future<FtpIntegrityValidationResult> _verifyByReadBack({
    required FTPConnect ftp,
    required String remoteFileName,
    required String localSha256,
  }) async {
    final tempFileName =
        '${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}_'
        '${p.basename(remoteFileName)}';
    final tempRemoteCopy = File(
      p.join(Directory.systemTemp.path, tempFileName),
    );

    Object? lastError;
    for (var attempt = 0; attempt < _integrityReadBackMaxAttempts; attempt++) {
      try {
        await _ensureBinaryTransferType(ftp);
        final downloaded = await ftp.downloadFile(
          remoteFileName,
          tempRemoteCopy,
        );
        if (!downloaded) {
          throw Exception('downloadFile retornou false');
        }

        final remoteSha = await computeSha256Streaming(tempRemoteCopy);
        if (remoteSha == null || remoteSha.isEmpty) {
          throw Exception('Não foi possível calcular SHA-256 do read-back');
        }

        if (remoteSha.toLowerCase() == localSha256.toLowerCase()) {
          LoggerService.info(
            'Integridade FTP validada por read-back para $remoteFileName',
          );
          return const FtpIntegrityValidationResult(isValid: true);
        }

        return FtpIntegrityValidationResult(
          isValid: false,
          errorMessage:
              'Falha de integridade no destino FTP: hash do arquivo '
              'baixado do servidor diverge do arquivo local. '
              'SHA local: $localSha256, SHA read-back: $remoteSha',
          originalError: Exception(
            'Divergência SHA-256 no read-back: '
            'local=$localSha256 remoto=$remoteSha',
          ),
        );
      } on Object catch (e) {
        lastError = e;
        if (attempt < _integrityReadBackMaxAttempts - 1) {
          await Future.delayed(_integrityReadBackRetryDelay);
        }
      } finally {
        try {
          if (await tempRemoteCopy.exists()) {
            await tempRemoteCopy.delete();
          }
        } on Object catch (e, st) {
          LoggerService.debug(
            'FTP integrity temp copy delete: $e',
            e,
            st,
          );
        }
      }
    }

    return FtpIntegrityValidationResult(
      isValid: false,
      failureCode: FailureCodes.ftpIntegrityValidationInconclusive,
      errorMessage:
          'Não foi possível confirmar a integridade por read-back após '
          '$_integrityReadBackMaxAttempts tentativas.',
      originalError: lastError ?? Exception('Read-back sem detalhes'),
    );
  }
}
