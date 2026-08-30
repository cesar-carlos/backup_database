import 'dart:io';
import 'dart:math';

import 'package:backup_database/core/errors/ftp_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_uploader.dart';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class FtpConnectionTester {
  FtpConnectionTester({FtpUploader? uploader})
    : _uploader = uploader ?? FtpUploader();

  final FtpUploader _uploader;

  static final _random = Random.secure();

  static String _randomSuffix() {
    final bytes = List<int>.generate(4, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

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
        allowInvalidCertificates: config.allowInvalidCertificates,
        showLog: config.enableVerboseLog || kDebugMode,
      );

      final connected = await ftp.connect();
      if (!connected) {
        return const rd.Success(
          FtpConnectionTestResult(connected: false),
        );
      }

      await _uploader.ensureBinaryTransferType(ftp);

      var canWrite = true;
      var canRename = true;

      if (config.remotePath.isNotEmpty && config.remotePath != '/') {
        await _uploader.createRemoteDirectories(ftp, config.remotePath);
        await ftp.changeDirectory(config.remotePath);
      }

      final testFileName =
          '_test_conn_${DateTime.now().millisecondsSinceEpoch}_'
          '${_randomSuffix()}.tmp';
      final testFileRenamed = '$testFileName.ok';

      final tempFile = File(
        p.join(
          Directory.systemTemp.path,
          '${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}_'
          'ftp_test.tmp',
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
            await _uploader.safeDeletePart(ftp, testFileName);
          } else {
            await _uploader.safeDeletePart(ftp, testFileRenamed);
          }
        }
      } finally {
        try {
          await tempFile.delete();
        } on Object catch (e, st) {
          LoggerService.debug(
            'FTP test temp delete: $e',
            e,
            st,
          );
        }
      }

      final supportsRestStream = await _uploader.checkRestStreamSupport(ftp);
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
}
