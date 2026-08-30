import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/destinations/local/local_atomic_copier.dart';
import 'package:backup_database/infrastructure/external/destinations/local/local_backup_retention.dart';
import 'package:backup_database/infrastructure/external/destinations/local/local_destination_errors.dart';
import 'package:backup_database/infrastructure/external/destinations/local/local_destination_path_lock.dart';
import 'package:backup_database/infrastructure/external/destinations/local/local_source_validator.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class LocalDestinationService implements ILocalDestinationService {
  final LocalDestinationPathLock _pathLock = LocalDestinationPathLock();
  final LocalAtomicCopier _atomicCopier = const LocalAtomicCopier();
  final LocalSourceValidator _sourceValidator = const LocalSourceValidator();
  final LocalBackupRetention _retention = const LocalBackupRetention();

  @override
  Future<rd.Result<LocalUploadResult>> upload({
    required String sourceFilePath,
    required LocalDestinationConfig config,
    String? customFileName,
    UploadProgressCallback? onProgress,
  }) {
    // Mantém o upload e o cleanup mutuamente exclusivos por destino
    // (mesmo `config.path`). Sem o lock, `cleanOldBackups` poderia
    // tentar apagar um `.tmp` em uso.
    return _pathLock.withLock(config.path, () async {
      return _uploadInternal(
        sourceFilePath: sourceFilePath,
        config: config,
        customFileName: customFileName,
        onProgress: onProgress,
      );
    });
  }

  Future<rd.Result<LocalUploadResult>> _uploadInternal({
    required String sourceFilePath,
    required LocalDestinationConfig config,
    String? customFileName,
    UploadProgressCallback? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Copiando para destino local: ${config.path}');

      final missingSource = await BackupArtifactUtils.missingSourceFileFailure(
        sourceFilePath,
      );
      if (missingSource != null) return rd.Failure(missingSource);
      final sourceFile = File(sourceFilePath);

      final sizeValidation = await _sourceValidator.validateWithRetry(
        sourceFile,
      );
      if (sizeValidation.isError()) {
        final error = sizeValidation.exceptionOrNull();
        final message = error is Failure
            ? error.message
            : error?.toString() ?? 'Erro desconhecido';
        return rd.Failure(
          FileSystemFailure(
            message:
                'Arquivo de origem inválido: $sourceFilePath\n'
                'O arquivo pode estar ainda sendo baixado ou travado pelo sistema.\n'
                'Detalhes: $message',
          ),
        );
      }

      var destinationDir = config.path;
      if (config.createSubfoldersByDate) {
        final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
        destinationDir = p.join(config.path, dateFolder);
      }

      final directory = Directory(destinationDir);
      try {
        if (!await directory.exists()) {
          await directory.create(recursive: true);
          LoggerService.debug('Diretório criado: $destinationDir');
        }
      } on FileSystemException catch (e) {
        stopwatch.stop();
        final errorMessage = LocalDestinationErrors.permissionMessage(
          e,
          destinationDir,
        );
        LoggerService.error('Erro ao criar diretório', e);
        return rd.Failure(
          FileSystemFailure(
            message: errorMessage,
            originalError: e,
          ),
        );
      }

      final canWrite = await DirectoryPermissionCheck.hasWritePermissionForPath(
        destinationDir,
      );
      if (!canWrite) {
        stopwatch.stop();
        return rd.Failure(
          FileSystemFailure(
            message:
                'Sem permissão de escrita no diretório: $destinationDir\n'
                'Verifique as permissões ou escolha outro diretório.',
          ),
        );
      }

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final destinationPath = p.join(destinationDir, fileName);

      try {
        final normalizedSource = p.normalize(p.absolute(sourceFilePath));
        final normalizedDest = p.normalize(p.absolute(destinationPath));
        final samePath =
            normalizedSource.toLowerCase() == normalizedDest.toLowerCase();
        if (samePath) {
          stopwatch.stop();
          LoggerService.warning(
            'Origem e destino são o mesmo arquivo (pasta temp = pasta final). '
            'Configure um destino final diferente da pasta temp.',
          );
          return const rd.Failure(
            FileSystemFailure(
              message:
                  'O destino final não pode ser a mesma pasta do arquivo temporário. '
                  'Configure em "Destinos" um caminho final diferente da pasta temp '
                  r'(ex.: temp = C:\Temp, destino final = D:\Backups).',
            ),
          );
        }

        LoggerService.info(
          'Iniciando cópia: $sourceFilePath -> $destinationPath',
        );

        final sourceFile = File(sourceFilePath);
        if (!await sourceFile.exists()) {
          throw FileSystemException(
            sourceFilePath,
            'Arquivo de origem não encontrado',
          );
        }

        final destinationFile = File(destinationPath);
        if (await destinationFile.exists()) {
          LoggerService.info('Arquivo de destino já existe, será sobrescrito');
          try {
            await destinationFile.delete();
            LoggerService.info('Arquivo de destino antigo removido');
          } on Object catch (e) {
            throw FileSystemException(
              destinationPath,
              'Não foi possível remover arquivo existente: $e',
            );
          }
        }

        LoggerService.info(
          'Executando cópia segura: $sourceFilePath -> $destinationPath',
        );

        await _atomicCopier.copyWithRetry(
          sourceFile: sourceFile,
          destinationPath: destinationPath,
          onProgress: onProgress,
        );

        LoggerService.info('Cópia atômica concluída com sucesso');

        stopwatch.stop();

        if (!await destinationFile.exists()) {
          throw FileSystemException(
            destinationPath,
            'Arquivo de destino não encontrado após cópia atômica',
          );
        }

        final copiedSize = await destinationFile.length();
        final sourceSize = await sourceFile.length();
        LoggerService.info('Tamanho do arquivo de origem: $sourceSize bytes');
        LoggerService.info('Tamanho do arquivo de destino: $copiedSize bytes');

        if (copiedSize != sourceSize) {
          return rd.Failure(
            FileSystemFailure(
              message:
                  'Falha de integridade no destino local: tamanho divergente '
                  'após cópia (origem: $sourceSize bytes, '
                  'destino: $copiedSize bytes).',
              code: FailureCodes.integrityValidationFailed,
              originalError: Exception(
                'Local copy size mismatch: source=$sourceSize '
                'destination=$copiedSize',
              ),
            ),
          );
        }

        // Validação SHA-256 é opcional para grandes backups: ler o
        // arquivo source uma terceira vez (após copy) custa ~ tamanho
        // do banco em I/O extra. Para a maioria dos cenários (mesmo
        // volume, sem rede), a checagem de tamanho acima já pega cópias
        // parciais. Backups críticos podem manter habilitado.
        if (config.enableHashValidation) {
          final sourceSha256 = await FileHashUtils.computeSha256(sourceFile);
          final destinationSha256 = await FileHashUtils.computeSha256(
            destinationFile,
          );
          if (destinationSha256.toLowerCase() != sourceSha256.toLowerCase()) {
            return rd.Failure(
              FileSystemFailure(
                message:
                    'Falha de integridade no destino local: hash SHA-256 do '
                    'arquivo copiado difere do arquivo de origem.',
                code: FailureCodes.integrityValidationFailed,
                originalError: Exception(
                  'Local copy SHA-256 mismatch: source=$sourceSha256 '
                  'destination=$destinationSha256',
                ),
              ),
            );
          }
        }

        LoggerService.info(
          'Arquivo copiado com sucesso: $destinationPath ($copiedSize bytes)',
        );

        onProgress?.call(1);

        return rd.Success(
          LocalUploadResult(
            destinationPath: destinationPath,
            fileSize: copiedSize,
            duration: stopwatch.elapsed,
          ),
        );
      } on FileSystemException catch (e) {
        stopwatch.stop();
        final errorMessage = LocalDestinationErrors.permissionMessage(
          e,
          destinationPath,
        );
        LoggerService.error('Erro ao copiar arquivo', e);
        return rd.Failure(
          FileSystemFailure(
            message: errorMessage,
            originalError: e,
          ),
        );
      }
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao copiar para destino local', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message:
              'Erro ao copiar arquivo para destino local: ${LocalDestinationErrors.userFriendly(e)}',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<bool>> testConnection(LocalDestinationConfig config) async {
    try {
      final directory = Directory(config.path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final canWrite = await DirectoryPermissionCheck.hasWritePermissionForPath(
        config.path,
      );
      if (!canWrite) {
        return rd.Failure(
          FileSystemFailure(
            message:
                'Sem permissão de escrita no diretório: ${config.path}\n'
                'Verifique as permissões ou escolha outro diretório.',
          ),
        );
      }
      return const rd.Success(true);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao testar conexão com diretório local',
        e,
        stackTrace,
      );
      return rd.Failure(
        FileSystemFailure(
          message:
              'Erro ao acessar diretório: ${LocalDestinationErrors.userFriendly(e)}',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<int>> cleanOldBackups({
    required LocalDestinationConfig config,
  }) {
    // Adquire o mesmo lock usado pelo `upload` para evitar race entre
    // limpeza por retenção e upload em andamento (apagar `.tmp` em uso).
    return _pathLock.withLock(
      config.path,
      () => _retention.cleanOldBackups(
        config: config,
      ),
    );
  }
}
