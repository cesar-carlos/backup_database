import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class LocalDestinationService implements ILocalDestinationService {
  /// Locks por path de destino para evitar que `cleanOldBackups` apague
  /// arquivos `.tmp` em uso por um upload concorrente, ou que dois
  /// uploads para o mesmo destino se atropelem.
  ///
  /// Usamos um `Completer<void>` por path: enquanto o lock está mantido,
  /// outras chamadas aguardam o `future`.
  static final Map<String, Future<void>> _destinationLocks = {};

  static Future<T> _withDestinationLock<T>(
    String destinationPath,
    Future<T> Function() operation,
  ) async {
    while (_destinationLocks.containsKey(destinationPath)) {
      try {
        await _destinationLocks[destinationPath];
      } on Object catch (_) {
        // Erro do owner anterior — não é problema do próximo na fila.
      }
    }
    final completer = Completer<void>();
    _destinationLocks[destinationPath] = completer.future;
    try {
      return await operation();
    } finally {
      _destinationLocks.remove(destinationPath);
      if (!completer.isCompleted) completer.complete();
    }
  }

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
    return _withDestinationLock(config.path, () async {
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

      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Arquivo de origem não encontrado: $sourceFilePath',
          ),
        );
      }

      final sizeValidation = await _validateSourceFileWithRetry(sourceFile);
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
        final errorMessage = _getPermissionErrorMessage(e, destinationDir);
        LoggerService.error('Erro ao criar diretório', e);
        return rd.Failure(
          FileSystemFailure(
            message: errorMessage,
            originalError: e,
          ),
        );
      }

      final canWrite = await _checkWritePermission(destinationDir);
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

        await _atomicCopyWithRetry(
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
        final errorMessage = _getPermissionErrorMessage(e, destinationPath);
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
              'Erro ao copiar arquivo para destino local: ${_getUserFriendlyError(e)}',
          originalError: e,
        ),
      );
    }
  }

  Future<void> _atomicCopyWithRetry({
    required File sourceFile,
    required String destinationPath,
    UploadProgressCallback? onProgress,
  }) async {
    const maxRetries = 3;
    var attempt = 0;
    Object? lastError;

    while (attempt < maxRetries) {
      attempt++;
      try {
        if (attempt > 1) {
          LoggerService.info(
            'Tentativa de cópia $attempt/$maxRetries para $destinationPath...',
          );

          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }

        await _atomicCopy(
          sourceFile: sourceFile,
          destinationPath: destinationPath,
          onProgress: onProgress,
        );
        return;
      } on Object catch (e) {
        lastError = e;
        LoggerService.warning(
          'Falha na tentativa $attempt/$maxRetries de copiar arquivo: $e',
        );

        if (e is FileSystemException && (e.osError?.errorCode == 5)) {
          rethrow;
        }
      }
    }

    if (lastError is Exception) throw lastError;
    if (lastError is Error) throw lastError;
    throw FileSystemException(
      'Falha ao copiar arquivo após $maxRetries tentativas',
      destinationPath,
    );
  }

  Future<void> _atomicCopy({
    required File sourceFile,
    required String destinationPath,
    UploadProgressCallback? onProgress,
  }) async {
    final tempDestinationPath = '$destinationPath.tmp';
    final tempFile = File(tempDestinationPath);
    final finalFile = File(destinationPath);

    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } on Object catch (e) {
        LoggerService.warning(
          'Não foi possível limpar arquivo temporário antigo: $tempDestinationPath',
          e,
        );
      }
    }

    final sourceSize = await sourceFile.length();

    try {
      await sourceFile.copyToWithBugFix(
        tempDestinationPath,
        onProgress: onProgress,
      );

      final tempSize = await tempFile.length();
      if (tempSize != sourceSize) {
        throw FileSystemException(
          'Tamanho do arquivo temporário incorreto. '
          'Esperado: $sourceSize, Encontrado: $tempSize',
          tempDestinationPath,
        );
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(destinationPath);
    } on Object catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on Object catch (_) {}
      }
      rethrow;
    }
  }

  Future<bool> _checkWritePermission(String path) async {
    try {
      final testFile = File(
        p.join(path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'),
      );
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } on Object catch (e, stackTrace) {
      LoggerService.debug(
        'Falha ao verificar permissão de escrita em: $path',
        e,
        stackTrace,
      );
      return false;
    }
  }

  Future<rd.Result<int>> _validateSourceFileWithRetry(File sourceFile) async {
    const maxAttempts = 10;
    const initialDelayMs = 100;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final size = await sourceFile.length();

        if (size > 0) {
          if (attempt > 0) {
            LoggerService.info(
              '[ValidateFile] Arquivo válido na tentativa ${attempt + 1}: $size bytes',
            );
          }
          return rd.Success(size);
        }

        LoggerService.warning(
          '[ValidateFile] Arquivo com 0 bytes na tentativa ${attempt + 1}, '
          'aguardando liberação...',
        );

        if (attempt < maxAttempts - 1) {
          final delay = initialDelayMs * (attempt + 1);
          await Future.delayed(Duration(milliseconds: delay));
        }
      } on FileSystemException catch (e) {
        LoggerService.warning(
          '[ValidateFile] Erro ao ler arquivo (tentativa ${attempt + 1}): $e',
        );

        if (attempt < maxAttempts - 1) {
          final delay = initialDelayMs * (attempt + 1);
          await Future.delayed(Duration(milliseconds: delay));
        } else {
          return rd.Failure(
            FileSystemFailure(
              message:
                  'Arquivo travado ou inacessível após $maxAttempts tentativas',
              originalError: e,
            ),
          );
        }
      } on Object catch (e) {
        LoggerService.error(
          '[ValidateFile] Erro inesperado ao validar arquivo',
          e,
        );
        return rd.Failure(
          FileSystemFailure(
            message: 'Erro inesperado ao validar arquivo: $e',
            originalError: e,
          ),
        );
      }
    }

    return const rd.Failure(
      FileSystemFailure(
        message:
            'Arquivo inválido (0 bytes) após $maxAttempts tentativas. '
            'O arquivo pode estar ainda sendo baixado.',
      ),
    );
  }

  String _getPermissionErrorMessage(FileSystemException e, String path) {
    if (e.osError?.errorCode == 5) {
      return 'Acesso negado ao diretório: $path\n'
          'Execute o aplicativo como Administrador ou escolha outro diretório.';
    } else if (e.osError?.errorCode == 3) {
      return 'Caminho não encontrado: $path\n'
          'Verifique se o disco ou pasta existe.';
    } else if (e.osError?.errorCode == 112) {
      return 'Disco cheio ou sem espaço suficiente: $path';
    }
    return 'Erro ao acessar: $path - ${e.message}';
  }

  String _getUserFriendlyError(dynamic e) {
    if (e is FileSystemException) {
      return _getPermissionErrorMessage(e, e.path ?? 'desconhecido');
    }
    return e.toString();
  }

  @override
  Future<rd.Result<bool>> testConnection(LocalDestinationConfig config) async {
    try {
      final directory = Directory(config.path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final canWrite = await _checkWritePermission(config.path);
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
          message: 'Erro ao acessar diretório: ${_getUserFriendlyError(e)}',
          originalError: e,
        ),
      );
    }
  }

  /// Extensões reconhecidas como "arquivos de backup" (ou seus
  /// derivados). Apenas arquivos cuja extensão termine com um destes
  /// sufixos serão considerados pelo `cleanOldBackups`. Antes, o cleanup
  /// apagava QUALQUER arquivo antigo na pasta — se o usuário tinha
  /// outros arquivos lá, eram perdidos.
  static const Set<String> _backupFileExtensions = {
    '.bak', // SQL Server
    '.trn', // SQL Server transaction log
    '.dump', // PostgreSQL pg_dump
    '.backup', // PostgreSQL backup
    '.tar', // PostgreSQL pg_basebackup tar
    '.db', // Sybase SA database file (usado em backups full)
    '.log', // Sybase transaction log
    '.sql', // SQL dump genérico
    '.zip',
    '.7z',
    '.gz',
    '.rar',
    '.bz2',
    '.xz',
    '.zst',
  };

  /// Identifica se o arquivo parece ser um artefato de backup (por
  /// extensão). Filtra `.tmp` (uploads em andamento) e qualquer outro
  /// arquivo que o usuário possa ter na pasta.
  static bool _looksLikeBackupArtifact(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.tmp')) return false;
    return _backupFileExtensions.any(lower.endsWith);
  }

  @override
  Future<rd.Result<int>> cleanOldBackups({
    required LocalDestinationConfig config,
  }) {
    // Adquire o mesmo lock usado pelo `upload` para evitar race entre
    // limpeza por retenção e upload em andamento (apagar `.tmp` em uso).
    return _withDestinationLock(config.path, () => _cleanOldBackupsInternal(
      config: config,
    ));
  }

  Future<rd.Result<int>> _cleanOldBackupsInternal({
    required LocalDestinationConfig config,
  }) async {
    try {
      LoggerService.info('Limpando backups antigos em: ${config.path}');

      final directory = Directory(config.path);
      if (!await directory.exists()) {
        return const rd.Success(0);
      }

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );
      final protected = config.protectedBackupIdShortPrefixes;

      var deletedCount = 0;
      var skippedNonBackup = 0;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is! File) continue;
        // Filtro por extensão: protege arquivos do usuário que estejam
        // na mesma pasta (configurações, anotações, etc.).
        if (!_looksLikeBackupArtifact(p.basename(entity.path))) {
          skippedNonBackup++;
          continue;
        }
        if (protected.isNotEmpty &&
            SybaseBackupPathSuffix.isPathProtected(entity.path, protected)) {
          LoggerService.debug(
            'Arquivo protegido (cadeia Sybase): ${entity.path}',
          );
          continue;
        }
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoffDate)) {
          await entity.delete();
          deletedCount++;
          LoggerService.debug('Arquivo deletado: ${entity.path}');
        }
      }

      await for (final entity in directory.list()) {
        if (entity is Directory) {
          final contents = await entity.list().toList();
          if (contents.isEmpty) {
            if (protected.isNotEmpty &&
                SybaseBackupPathSuffix.isPathProtected(
                  entity.path,
                  protected,
                )) {
              LoggerService.debug(
                'Diretório protegido (cadeia Sybase): ${entity.path}',
              );
              continue;
            }
            await entity.delete();
            LoggerService.debug('Diretório vazio removido: ${entity.path}');
          }
        }
      }

      LoggerService.info(
        '$deletedCount arquivo(s) antigo(s) removido(s) '
        '($skippedNonBackup arquivo(s) não-backup preservado(s))',
      );
      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao limpar backups antigos', e, stackTrace);
      return rd.Failure(
        FileSystemFailure(
          message: 'Erro ao limpar backups antigos: $e',
          originalError: e,
        ),
      );
    }
  }
}

extension FileCopyWithProgress on File {
  static int get _chunkSize => UploadChunkConstants.localCopyChunkSize;

  Future<void> copyToWithBugFix(
    String newPath, {
    UploadProgressCallback? onProgress,
  }) async {
    LoggerService.debug(
      '[CopyDebug] Iniciando copyToWithBugFix: $path -> $newPath',
    );

    final sourceRaf = await _openWithRetry();
    RandomAccessFile? destRaf;

    try {
      LoggerService.debug(
      '[CopyDebug] Source aberto. Abrindo destino...');
      destRaf = await File(newPath).open(mode: FileMode.write);
      LoggerService.debug(
      '[CopyDebug] Destino aberto (RAF). Iniciando loop...');

      final fileSize = await sourceRaf.length();
      var bytesCopied = 0;
      var loopCount = 0;

      while (bytesCopied < fileSize) {
        loopCount++;
        final bytesToRead = _chunkSize < (fileSize - bytesCopied)
            ? _chunkSize
            : (fileSize - bytesCopied);
        final buffer = List<int>.filled(bytesToRead, 0);

        final bytesRead = await sourceRaf.readInto(buffer, 0, bytesToRead);

        if (bytesRead == 0 && bytesToRead > 0) {
          throw FileSystemException(
            'Leitura interrompida inesperadamente (0 bytes lidos) na posição $bytesCopied',
            newPath,
          );
        }

        if (bytesRead < bytesToRead) {
          await destRaf.writeFrom(buffer, 0, bytesRead);
          bytesCopied += bytesRead;
        } else {
          await destRaf.writeFrom(buffer);
          bytesCopied += bytesToRead;
        }

        if (loopCount % 10 == 0 || bytesCopied == fileSize) {
          LoggerService.debug(
            '[CopyDebug] Loop $loopCount: $bytesCopied/$fileSize bytes copiados',
          );
        }

        if (onProgress != null && fileSize > 0) {
          final progress = bytesCopied / fileSize;
          onProgress(progress);
        }
      }
      LoggerService.debug(
      '[CopyDebug] Loop finalizado. Efetuando flush...');
      await destRaf.flush();
      LoggerService.debug(
      '[CopyDebug] Flush OK.');
    } on Object catch (e, st) {
      LoggerService.error('[CopyDebug] Erro durante cópia: $e', e, st);
      rethrow;
    } finally {
      LoggerService.debug(
      '[CopyDebug] Fechando arquivos...');
      try {
        await sourceRaf.close();
        LoggerService.debug(
      '[CopyDebug] Source fechado.');
      } on Object catch (e) {
        LoggerService.warning('[CopyDebug] Erro ao fechar source: $e');
      }
      try {
        await destRaf?.close();
        LoggerService.debug(
      '[CopyDebug] Destino fechado.');
      } on Object catch (e) {
        LoggerService.warning('[CopyDebug] Erro ao fechar destino: $e');
      }
    }
  }

  Future<RandomAccessFile> _openWithRetry([int retries = 3]) async {
    var attempt = 0;
    while (true) {
      try {
        attempt++;
        return await open();
      } catch (e) {
        if (attempt >= retries) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }
}
