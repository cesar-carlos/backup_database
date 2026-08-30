import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/services/i_send_file_to_destination_service.dart';
import 'package:flutter/foundation.dart';

typedef TransferProgressCallback = void Function(
  String step,
  String message,
  double progress,
);

class RemoteFileDestinationUploader {
  RemoteFileDestinationUploader({
    required this._destinationRepository,
    required this._sendFileToDestinationService,
    required this._notifyListeners,
    required this._setUploading,
    required this._setUploadError,
  });

  final IBackupDestinationRepository _destinationRepository;
  final ISendFileToDestinationService _sendFileToDestinationService;
  final VoidCallback _notifyListeners;
  final void Function(bool isUploading) _setUploading;
  final void Function(String? error) _setUploadError;

  Future<void> uploadToSelected({
    required String localFilePath,
    required Set<String> destinationIds,
  }) async {
    if (destinationIds.isEmpty) {
      return;
    }

    _setUploading(true);
    _setUploadError(null);
    _notifyListeners();

    final errors = <String>[];
    for (final id in destinationIds) {
      final destResult = await _destinationRepository.getById(id);

      final destination = destResult.fold(
        (dest) => dest,
        (_) {
          errors.add('Destino $id não encontrado');
          return null;
        },
      );

      if (destination == null) continue;

      LoggerService.info('Enviando para destino: ${destination.name}');

      final sendResult = await _sendFileToDestinationService.sendFile(
        localFilePath: localFilePath,
        destination: destination,
      );

      sendResult.fold(
        (_) {
          LoggerService.info('Upload concluído: ${destination.name}');
        },
        (failure) {
          final msg = failureUserMessage(failure);
          LoggerService.warning(
            'Erro ao enviar para ${destination.name}: $msg',
          );
          errors.add('${destination.name}: $msg');
        },
      );
    }

    _setUploading(false);
    _setUploadError(errors.isEmpty ? null : errors.join('; '));
    _notifyListeners();
  }

  Future<bool> uploadToLinked({
    required String outputFilePath,
    required List<String> linkedIds,
    required TransferProgressCallback? onTransferProgress,
  }) async {
    LoggerService.info(
      'Iniciando upload para ${linkedIds.length} destinos vinculados',
    );

    _setUploading(true);
    _setUploadError(null);
    _notifyListeners();

    final errors = <String>[];
    var completedUploads = 0;

    for (final id in linkedIds) {
      final uploadProgress = completedUploads / linkedIds.length;
      onTransferProgress?.call(
        'Enviando para destinos',
        'Processando destino ${completedUploads + 1} de ${linkedIds.length}',
        uploadProgress,
      );

      final destResult = await _destinationRepository.getById(id);
      final destination = destResult.fold((dest) => dest, (_) => null);
      if (destination == null) {
        final errMsg = 'Destino $id não encontrado';
        LoggerService.warning(errMsg);
        errors.add(errMsg);
        completedUploads++;
        continue;
      }

      LoggerService.debug('Enviando para destino: ${destination.name}');
      onTransferProgress?.call(
        'Enviando para ${destination.name}',
        'Iniciando upload...',
        uploadProgress,
      );

      final sendResult = await _sendFileToDestinationService.sendFile(
        localFilePath: outputFilePath,
        destination: destination,
        onProgress: (uploadProgressValue, [String? stepOverride]) {
          final baseProgress = completedUploads / linkedIds.length;
          final destinationProgress =
              (1 / linkedIds.length) * uploadProgressValue;
          final totalProgress = baseProgress + destinationProgress;
          onTransferProgress?.call(
            stepOverride ?? 'Enviando para ${destination.name}',
            '${(uploadProgressValue * 100).toStringAsFixed(1)}%',
            totalProgress,
          );
        },
      );

      sendResult.fold(
        (_) {
          LoggerService.info('Upload concluído: ${destination.name}');
          completedUploads++;
          onTransferProgress?.call(
            'Enviando para ${destination.name}',
            'Concluído',
            completedUploads / linkedIds.length,
          );
        },
        (failure) {
          final errMsg = '${destination.name}: ${failureUserMessage(failure)}';
          LoggerService.error(
            'Erro no upload para ${destination.name}',
            failure,
          );
          errors.add(errMsg);
        },
      );
    }

    _setUploading(false);
    _setUploadError(errors.isEmpty ? null : errors.join('; '));
    _notifyListeners();

    if (errors.isEmpty) {
      LoggerService.info('Todos os uploads concluídos com sucesso');
    } else {
      LoggerService.warning(
        'Uploads concluídos com erros: ${errors.join('; ')}',
      );
    }
    return errors.isNotEmpty;
  }
}
