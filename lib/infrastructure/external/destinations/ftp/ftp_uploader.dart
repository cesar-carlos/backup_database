import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/ftp_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_integrity_verifier.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp_upload_offset_decision.dart';
import 'package:ftpconnect/ftpconnect.dart';

class FtpPartUploadResult {
  const FtpPartUploadResult({required this.uploaded, required this.resumed});
  final bool uploaded;
  final bool resumed;
}

class FtpResumeNotSupportedPolicyException implements Exception {
  FtpResumeNotSupportedPolicyException(this.failure);
  final FtpFailure failure;
}

class FtpUploader {
  FtpUploader({FtpIntegrityVerifier? integrityVerifier})
    : _integrityVerifier = integrityVerifier ?? FtpIntegrityVerifier();

  final FtpIntegrityVerifier _integrityVerifier;

  /// Incremento mínimo de progresso (em %) entre logs consecutivos no
  /// caminho de resume. Evita explosão de logs idênticos em arquivos
  /// grandes (anti-padrão "throttle por módulo" em
  /// `architectural_patterns.mdc` §5.5).
  static const _resumeLogPercentStep = 10;

  Timer? startCancellationWatcher({
    required FTPConnect ftp,
    required bool Function()? isCancelled,
    required String context,
  }) {
    if (isCancelled == null) {
      return null;
    }
    var disconnectStarted = false;
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isCancelled()) return;
      timer.cancel();
      if (disconnectStarted) return;
      disconnectStarted = true;
      LoggerService.info(
        '${context}Cancelamento FTP detectado; encerrando conexão',
      );
      unawaited(
        ftp.disconnect().catchError((Object e, StackTrace st) {
          LoggerService.debug(
            'FTP disconnect after cancellation signal: $e',
            e,
            st,
          );
          return false;
        }),
      );
    });
  }

  Future<FtpPartUploadResult> performUploadWithResume({
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
        throw const UploadCancelledException();
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
        return const FtpPartUploadResult(uploaded: true, resumed: false);

      case FtpUploadResume(:final offset):
        LoggerService.info(
          'Retomando upload de $remotePartName a partir do byte $offset',
        );
        var lastLoggedResumePercent = -1;
        final uploaded = await ftp.uploadFileWithResume(
          sourceFile,
          offset: offset,
          sRemoteName: remotePartName,
          onProgress: (p, s, t) {
            final percent = p.toInt();
            String? step;
            if (percent >= lastLoggedResumePercent + _resumeLogPercentStep) {
              step = 'Retomando de $percent%';
              lastLoggedResumePercent = percent;
            }
            ftpProgressAdapter(p, s, t, stepOverride: step);
          },
        );
        return FtpPartUploadResult(uploaded: uploaded, resumed: true);

      case FtpUploadFullUpload():
        if (remoteSize > fileSize) {
          LoggerService.debug(
            'Parcial remoto ($remoteSize) maior que local ($fileSize); '
            'removendo e reiniciando upload',
          );
          await safeDeletePart(ftp, remotePartName);
        } else if (remoteSize > 0 && !effectiveSupportsRest) {
          if (whenResumeNotSupportedFail) {
            throw FtpResumeNotSupportedPolicyException(
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
          await safeDeletePart(ftp, remotePartName);
        }
        final uploaded = await ftp.uploadFile(
          sourceFile,
          sRemoteName: remotePartName,
          onProgress: ftpProgressAdapter,
        );
        return FtpPartUploadResult(uploaded: uploaded, resumed: false);
    }
  }

  Future<bool> isRemoteFileAlreadyComplete({
    required FTPConnect ftp,
    required String remoteFileName,
    required int expectedSize,
    required String? localSha256,
    required bool enableStrongIntegrityValidation,
    required bool enableReadBackValidation,
  }) async {
    final remoteSize = await ftp.sizeFile(remoteFileName);
    if (remoteSize == -1) {
      return false;
    }
    if (remoteSize != expectedSize) {
      LoggerService.warning(
        'Arquivo final já existe no FTP com tamanho diferente '
        '(remoto=$remoteSize, local=$expectedSize): $remoteFileName',
      );
      return false;
    }

    final integrityResult = await _integrityVerifier.validateFinalIntegrity(
      ftp: ftp,
      remoteFileName: remoteFileName,
      expectedSize: expectedSize,
      localSha256: localSha256,
      enableStrongIntegrityValidation: enableStrongIntegrityValidation,
      enableReadBackValidation: enableReadBackValidation,
    );
    if (!integrityResult.isValid) {
      LoggerService.warning(
        'Arquivo final existente no FTP não passou na validação de '
        'integridade. Upload completo será tentado novamente: '
        '${integrityResult.errorMessage}',
      );
      return false;
    }

    return true;
  }

  Future<void> safeDeletePart(FTPConnect ftp, String remotePartName) async {
    try {
      await ftp.deleteFile(remotePartName);
    } on Object catch (e) {
      LoggerService.warning(
        'Não foi possível remover arquivo temporário: $e',
      );
    }
  }

  Future<void> ensureBinaryTransferType(FTPConnect ftp) async {
    try {
      await ftp.setTransferType(TransferType.binary);
    } on Object catch (e) {
      LoggerService.warning(
        'Não foi possível fixar transferência em modo binário (TYPE I): $e',
      );
    }
  }

  Future<void> createRemoteDirectories(FTPConnect ftp, String path) async {
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

  Future<bool?> checkRestStreamSupport(FTPConnect ftp) async {
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
}
