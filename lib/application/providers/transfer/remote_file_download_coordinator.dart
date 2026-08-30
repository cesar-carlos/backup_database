import 'dart:io' show File;

import 'package:backup_database/application/providers/transfer/remote_file_destination_uploader.dart';
import 'package:backup_database/application/providers/transfer/transfer_retry.dart';
import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class RemoteFileTransferUiHooks {
  const RemoteFileTransferUiHooks({
    required this.beginTransfer,
    required this.onChunkProgress,
    required this.endTransfer,
    required this.notify,
  });

  final void Function() beginTransfer;
  final void Function(int currentChunk, int totalChunks) onChunkProgress;
  final void Function({String? error}) endTransfer;
  final void Function() notify;
}

class RemoteFileDownloadCoordinator {
  RemoteFileDownloadCoordinator({
    required this._connectionManager,
    required this._tempDirectoryService,
    required this._uploader,
    required this._ui,
  });

  final ConnectionManager _connectionManager;
  final TempDirectoryService _tempDirectoryService;
  final RemoteFileDestinationUploader _uploader;
  final RemoteFileTransferUiHooks _ui;

  Future<rd.Result<void>> downloadFile({
    required String filePath,
    required String outputPath,
    String? scheduleId,
    String? runId,
    String? operationName,
    TransferProgressCallback? onTransferProgress,
  }) {
    return TransferRetry.execute(
      () => _connectionManager.requestFile(
        filePath: filePath,
        outputPath: outputPath,
        scheduleId: scheduleId,
        runId: runId,
        onProgress: (currentChunk, totalChunks) {
          _ui.onChunkProgress(currentChunk, totalChunks);
          if (onTransferProgress != null && totalChunks > 0) {
            final progress = currentChunk / totalChunks;
            onTransferProgress(
              'Baixando arquivo do servidor',
              'Transferindo: ${(progress * 100).toStringAsFixed(1)}%',
              progress,
            );
          }
        },
      ),
      operationName: operationName ?? 'Download file $filePath',
    );
  }

  Future<bool> transferCompletedBackupToClient({
    required String scheduleId,
    required String relativePath,
    required List<String> linkedIds,
    required String? Function(String relativePath) stagingDirectoryKey,
    String? runId,
    TransferProgressCallback? onTransferProgress,
  }) async {
    LoggerService.info(
      'Iniciando transferência de backup: scheduleId=$scheduleId, '
      'relativePath=$relativePath',
    );

    if (!_connectionManager.isConnected) {
      LoggerService.error('Cliente não está conectado ao servidor');
      return false;
    }

    LoggerService.debug(
      'Destinos vinculados: ${linkedIds.length} '
      '${linkedIds.isEmpty ? '' : '(${linkedIds.join(', ')})'}',
    );

    final downloadsDir = await _tempDirectoryService.getDownloadsDirectory();
    final destDir = downloadsDir.path;

    final baseName = p.basename(relativePath);
    final outputFileName = p.extension(baseName).isEmpty
        ? '$baseName.zip'
        : baseName;
    final outputFilePath = p.join(destDir, outputFileName);
    LoggerService.debug('Caminho de download: $outputFilePath');

    _ui.beginTransfer();

    onTransferProgress?.call(
      'Baixando arquivo do servidor',
      'Iniciando transferência...',
      0,
    );

    final result = await downloadFile(
      filePath: relativePath,
      outputPath: outputFilePath,
      scheduleId: scheduleId,
      runId: runId,
      operationName: 'Download backup $scheduleId',
      onTransferProgress: onTransferProgress,
    );

    final success = result.fold(
      (_) {
        _ui.endTransfer();
        LoggerService.info('Download de backup concluído: $outputFilePath');
        return true;
      },
      (failure) {
        _ui.endTransfer(
          error:
              'Falha ao baixar backup após ${SocketConfig.maxRetries} '
              'tentativas: ${failureUserMessage(failure)}',
        );
        LoggerService.error('Falha no download de backup', failure);
        return false;
      },
    );

    if (success) {
      final downloadedFile = File(outputFilePath);
      if (!await downloadedFile.exists()) {
        final error =
            'Arquivo baixado não encontrado após transferência: '
            '$outputFilePath';
        _ui.endTransfer(error: error);
        LoggerService.error(error);
        _ui.notify();
        return false;
      }
      final downloadedSize = await downloadedFile.length();
      if (downloadedSize == 0) {
        const error =
            'Arquivo baixado está vazio (0 bytes). Não é possível enviar '
            'para destinos. Verifique o backup no servidor.';
        _ui.endTransfer(error: error);
        LoggerService.error(error);
        _ui.notify();
        return false;
      }
      LoggerService.info(
        'Arquivo baixado verificado: $outputFilePath ($downloadedSize bytes)',
      );

      final stagingKey = stagingDirectoryKey(relativePath) ?? runId;
      if (stagingKey != null && stagingKey.isNotEmpty) {
        final remoteCleanup = await _connectionManager.cleanupRemoteStaging(
          runId: stagingKey,
        );
        remoteCleanup.fold(
          (_) {
            LoggerService.debug('Limpeza do staging no servidor: $stagingKey');
          },
          (failure) {
            LoggerService.warning(
              'Falha ao solicitar limpeza do staging remoto (não crítico): '
              '${failureUserMessage(failure)}',
            );
          },
        );
      } else {
        LoggerService.debug(
          'Caminho relativo sem padrão remote/<chave>/; '
          'limpeza remota ignorada: $relativePath',
        );
      }

      var uploadHadErrors = false;
      if (linkedIds.isNotEmpty) {
        uploadHadErrors = await _uploader.uploadToLinked(
          outputFilePath: outputFilePath,
          linkedIds: linkedIds,
          onTransferProgress: onTransferProgress,
        );
      } else {
        LoggerService.debug('Nenhum destino vinculado, pulando upload');
      }

      if (!uploadHadErrors) {
        await _safeDeleteTempFile(outputFilePath);
      } else {
        LoggerService.info(
          'Arquivo temporário preservado para retry: $outputFilePath',
        );
      }
    }

    LoggerService.info(
      'Transferência finalizada: ${success ? 'SUCESSO' : 'FALHA'}',
    );

    _ui.notify();
    return success;
  }

  Future<void> _safeDeleteTempFile(String path) async {
    try {
      final tempFile = File(path);
      if (await tempFile.exists()) {
        await tempFile.delete();
        LoggerService.debug('Arquivo temporário removido: $path');
      }
    } on Object catch (e) {
      LoggerService.warning('Não foi possível remover arquivo temporário: $e');
    }
  }
}
