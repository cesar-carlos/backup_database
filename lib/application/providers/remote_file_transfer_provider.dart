import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/services/i_send_file_to_destination_service.dart';
import 'package:backup_database/domain/services/i_transfer_staging_service.dart';
import 'package:backup_database/infrastructure/datasources/daos/file_transfer_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

typedef TransferProgressCallback =
    void Function(
      String step,
      String message,
      double progress,
    );

class RemoteFileTransferProvider extends ChangeNotifier {
  RemoteFileTransferProvider(
    this._connectionManager,
    this._destinationRepository,
    this._sendFileToDestinationService, {
    FileTransferDao? fileTransferDao,
  }) : _fileTransferDao = fileTransferDao;

  final ConnectionManager _connectionManager;
  final IBackupDestinationRepository _destinationRepository;
  final ISendFileToDestinationService _sendFileToDestinationService;
  final FileTransferDao? _fileTransferDao;

  ITransferStagingService? _stagingServiceCache;

  List<RemoteFileEntry> _files = [];
  RemoteFileEntry? _selectedFile;
  String _outputPath = '';
  bool _isLoading = false;
  bool _isTransferring = false;
  int? _transferCurrentChunk;
  int? _transferTotalChunks;
  List<FileTransferHistoryEntry> _transferHistory = [];
  String? _error;
  final Set<String> _selectedDestinationIds = {};
  bool _isUploadingToRemotes = false;
  String? _uploadError;

  List<RemoteFileEntry> get files => _files;
  List<FileTransferHistoryEntry> get transferHistory => _transferHistory;
  RemoteFileEntry? get selectedFile => _selectedFile;
  String get outputPath => _outputPath;
  bool get isLoading => _isLoading;
  bool get isTransferring => _isTransferring;
  int? get transferCurrentChunk => _transferCurrentChunk;
  int? get transferTotalChunks => _transferTotalChunks;
  double? get transferProgress =>
      _transferTotalChunks != null &&
          _transferTotalChunks! > 0 &&
          _transferCurrentChunk != null
      ? (_transferCurrentChunk! / _transferTotalChunks!).clamp(0.0, 1.0)
      : null;
  String? get error => _error;
  Set<String> get selectedDestinationIds =>
      Set<String>.unmodifiable(_selectedDestinationIds);
  bool get isUploadingToRemotes => _isUploadingToRemotes;
  String? get uploadError => _uploadError;
  bool get isConnected => _connectionManager.isConnected;

  ITransferStagingService get _transferStagingService =>
      _stagingServiceCache ??= getIt<ITransferStagingService>();

  void setSelectedFile(RemoteFileEntry? entry) {
    _selectedFile = entry;
    notifyListeners();
  }

  void setOutputPath(String path) {
    _outputPath = path;
    notifyListeners();
  }

  void setSelectedDestinationIds(Set<String> ids) {
    _selectedDestinationIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void toggleSelectedDestination(String id) {
    if (_selectedDestinationIds.contains(id)) {
      _selectedDestinationIds.remove(id);
    } else {
      _selectedDestinationIds.add(id);
    }
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearUploadError() {
    _uploadError = null;
    notifyListeners();
  }

  Future<String?> getDefaultOutputPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.receivedBackupsDefaultPathKey);
  }

  Future<void> setDefaultOutputPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.receivedBackupsDefaultPathKey, trimmed);
  }

  Future<List<String>> getLinkedDestinationIds(String scheduleId) async {
    if (scheduleId.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(AppConstants.scheduleTransferDestinationsKey);
    if (json == null || json.isEmpty) return [];
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final list = map[scheduleId];
      if (list == null) return [];
      return (list as List<dynamic>).cast<String>();
    } on Object catch (_) {
      return [];
    }
  }

  Future<void> setLinkedDestinationIds(
    String scheduleId,
    List<String> destinationIds,
  ) async {
    if (scheduleId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(AppConstants.scheduleTransferDestinationsKey);
    var map = <String, dynamic>{};
    if (json != null && json.isNotEmpty) {
      try {
        map = Map<String, dynamic>.from(
          jsonDecode(json) as Map<String, dynamic>,
        );
      } on Object catch (_) {
        map = {};
      }
    }
    map[scheduleId] = destinationIds;
    await prefs.setString(
      AppConstants.scheduleTransferDestinationsKey,
      jsonEncode(map),
    );
    notifyListeners();
  }

  Future<void> loadAvailableFiles() async {
    if (!_connectionManager.isConnected) {
      _error = 'Não conectado ao servidor';
      notifyListeners();
      return;
    }

    if (_outputPath.isEmpty) {
      final defaultPath = await getDefaultOutputPath();
      if (defaultPath != null && defaultPath.isNotEmpty) {
        _outputPath = defaultPath;
        notifyListeners();
      }
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _connectionManager.listAvailableFiles();

    result.fold(
      (list) {
        _files = list;
        _isLoading = false;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<void> loadTransferHistory() async {
    if (_fileTransferDao == null) return;
    final list = await _fileTransferDao.getAll();
    list.sort(
      (a, b) => (b.completedAt ?? DateTime(0)).compareTo(
        a.completedAt ?? DateTime(0),
      ),
    );
    _transferHistory = list.take(50).map(_toHistoryEntry).toList();
    notifyListeners();
  }

  static FileTransferHistoryEntry _toHistoryEntry(FileTransfersTableData d) =>
      FileTransferHistoryEntry(
        id: d.id,
        fileName: d.fileName,
        fileSize: d.fileSize,
        status: d.status,
        completedAt: d.completedAt,
        sourcePath: d.sourcePath,
        destinationPath: d.destinationPath,
        errorMessage: d.errorMessage,
      );

  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = SocketConfig.maxRetries,
    Duration initialDelay = SocketConfig.downloadRetryInitialDelay,
    Duration maxDelay = SocketConfig.downloadRetryMaxDelay,
    int backoffMultiplier = SocketConfig.downloadRetryBackoffMultiplier,
    String? operationName,
  }) async {
    var attempt = 0;
    var delay = initialDelay;

    while (true) {
      attempt++;
      final name = operationName ?? 'Operation';

      try {
        return await operation();
      } on Object catch (e, st) {
        final isLastAttempt = attempt >= maxAttempts;

        LoggerService.warning(
          '$name failed (attempt $attempt/$maxAttempts): $e',
          e,
          st,
        );

        if (isLastAttempt) {
          LoggerService.error('$name failed after $maxAttempts attempts');
          rethrow;
        }

        LoggerService.info(
          'Retrying $name in ${delay.inSeconds}s '
          '(attempt ${attempt + 1}/$maxAttempts)',
        );

        await Future.delayed(delay);

        final nextDelayMs = delay.inMilliseconds * backoffMultiplier;
        final nextDelay = Duration(milliseconds: nextDelayMs);

        delay = nextDelay < maxDelay ? nextDelay : maxDelay;
      }
    }
  }

  Future<bool> requestFile() async {
    final selected = _selectedFile;
    if (selected == null || _outputPath.trim().isEmpty) {
      _error = 'Selecione um arquivo e o destino';
      notifyListeners();
      return false;
    }
    if (!_connectionManager.isConnected) {
      _error = 'Não conectado ao servidor';
      notifyListeners();
      return false;
    }

    _isTransferring = true;
    _error = null;
    _transferCurrentChunk = null;
    _transferTotalChunks = null;
    notifyListeners();

    final startedAt = DateTime.now();
    final destDir = _outputPath.trim();
    final outputFilePath = p.join(destDir, p.basename(selected.path));

    final result = await _executeWithRetry(
      () => _connectionManager.requestFile(
        filePath: selected.path,
        outputPath: outputFilePath,
        onProgress: (currentChunk, totalChunks) {
          _transferCurrentChunk = currentChunk;
          _transferTotalChunks = totalChunks;
          notifyListeners();
        },
      ),
      operationName: 'Download file ${selected.path}',
    );

    final totalChunks = _transferTotalChunks ?? 0;
    _isTransferring = false;
    _transferCurrentChunk = null;
    _transferTotalChunks = null;

    final success = result.fold(
      (_) {
        _error = null;
        return true;
      },
      (failure) {
        _error =
            'Falha ao baixar arquivo após ${SocketConfig.maxRetries} tentativas: $failure';
        return false;
      },
    );

    if (_fileTransferDao != null) {
      try {
        await _fileTransferDao.insertTransfer(
          FileTransfersTableCompanion.insert(
            id: const Uuid().v4(),
            scheduleId: '',
            fileName: p.basename(selected.path),
            fileSize: selected.size,
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            status: success ? 'completed' : 'failed',
            errorMessage: success ? const Value.absent() : Value(_error),
            startedAt: Value(startedAt),
            completedAt: Value(DateTime.now()),
            sourcePath: selected.path,
            destinationPath: outputFilePath,
            checksum: '',
          ),
        );
      } on Object catch (_) {}
      loadTransferHistory();
    }

    if (success && _selectedDestinationIds.isNotEmpty) {
      _isUploadingToRemotes = true;
      _uploadError = null;
      notifyListeners();

      final errors = <String>[];
      for (final id in _selectedDestinationIds) {
        final destResult = await _destinationRepository.getById(id);

        final destination = destResult.fold(
          (dest) => dest,
          (failure) {
            errors.add('Destino $id não encontrado');
            return null;
          },
        );

        if (destination == null) continue;

        LoggerService.info('Enviando para destino: ${destination.name}');

        final sendResult = await _sendFileToDestinationService.sendFile(
          localFilePath: outputFilePath,
          destination: destination,
        );

        sendResult.fold(
          (_) {
            LoggerService.info('Upload concluído: ${destination.name}');
          },
          (failure) {
            LoggerService.warning(
              'Erro ao enviar para ${destination.name}: $failure',
            );
            errors.add('${destination.name}: $failure');
          },
        );
      }

      _isUploadingToRemotes = false;
      _uploadError = errors.isEmpty ? null : errors.join('; ');
      notifyListeners();
    }

    notifyListeners();
    return success;
  }

  static const String _receivedBackupsSubdir = 'ReceivedBackups';

  Future<bool> transferCompletedBackupToClient(
    String scheduleId,
    String relativePath, {
    TransferProgressCallback? onTransferProgress,
  }) async {
    LoggerService.info('===== INÍCIO TRANSFERÊNCIA BACKUP PARA CLIENTE =====');
    LoggerService.info('ScheduleID: $scheduleId');
    LoggerService.info('RelativePath recebido do servidor: $relativePath');

    if (!_connectionManager.isConnected) {
      LoggerService.error('Cliente não está conectado ao servidor!');
      return false;
    }
    LoggerService.info('Cliente conectado ao servidor ✓');

    final linkedIds = await getLinkedDestinationIds(scheduleId);
    LoggerService.info(
      'Destinos vinculados encontrados: ${linkedIds.length} destinos',
    );
    if (linkedIds.isNotEmpty) {
      LoggerService.info('IDs dos destinos: ${linkedIds.join(', ')}');
    }

    String destDir;
    String? tempPathForCleanup;

    if (linkedIds.isNotEmpty) {
      LoggerService.info(
        'Buscando tempPath do primeiro destino vinculado: ${linkedIds.first}',
      );
      final firstDestResult = await _destinationRepository.getById(
        linkedIds.first,
      );
      final firstDest = firstDestResult.fold(
        (dest) {
          LoggerService.info('Destino encontrado: ${dest.name}');
          return dest;
        },
        (failure) {
          LoggerService.warning('Destino não encontrado: $failure');
          return null;
        },
      );

      if (firstDest?.tempPath != null && firstDest!.tempPath!.isNotEmpty) {
        destDir = firstDest.tempPath!;
        tempPathForCleanup = firstDest.tempPath;
        LoggerService.info('✓ tempPath configurado: $destDir');
        LoggerService.info('✓ Usando tempPath do destino "${firstDest.name}"');
      } else {
        LoggerService.warning(
          '⚠ tempPath não configurado no destino, usando outputPath padrão',
        );
        destDir = _outputPath.trim();
      }
    } else {
      LoggerService.warning(
        '⚠ Nenhum destino vinculado, usando outputPath padrão',
      );
      destDir = _outputPath.trim();
    }

    if (destDir.isEmpty) {
      LoggerService.info('destDir vazio, buscando caminho padrão...');
      final defaultPath = await getDefaultOutputPath();
      if (defaultPath != null && defaultPath.isNotEmpty) {
        destDir = defaultPath;
        LoggerService.info('Usando defaultPath: $destDir');
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        destDir = p.join(appDir.path, _receivedBackupsSubdir);
        LoggerService.info('Usando appDir + ReceivedBackups: $destDir');
      }
    }

    LoggerService.info('Diretório final de download: $destDir');

    final dir = Directory(destDir);
    if (!await dir.exists()) {
      LoggerService.info('Criando diretório de download: $destDir');
      await dir.create(recursive: true);
    }

    final outputFilePath = p.join(destDir, p.basename(relativePath));
    LoggerService.info('Caminho completo do arquivo: $outputFilePath');

    _isTransferring = true;
    _error = null;
    _transferCurrentChunk = null;
    _transferTotalChunks = null;
    notifyListeners();

    LoggerService.info('===== INICIANDO DOWNLOAD =====');
    LoggerService.info('Solicitando arquivo: $relativePath');
    LoggerService.info('Salvando em: $outputFilePath');

    onTransferProgress?.call(
      'Baixando arquivo do servidor',
      'Iniciando transferência...',
      0,
    );

    final result = await _executeWithRetry(
      () => _connectionManager.requestFile(
        filePath: relativePath,
        outputPath: outputFilePath,
        scheduleId: scheduleId,
        onProgress: (currentChunk, totalChunks) {
          _transferCurrentChunk = currentChunk;
          _transferTotalChunks = totalChunks;
          notifyListeners();
          final progress = totalChunks > 0 ? currentChunk / totalChunks : 0.0;
          onTransferProgress?.call(
            'Baixando arquivo do servidor',
            'Transferindo: ${(progress * 100).toStringAsFixed(1)}%',
            progress,
          );
          LoggerService.debug('Progresso: $currentChunk/$totalChunks chunks');
        },
      ),
      operationName: 'Download backup $scheduleId',
    );

    _isTransferring = false;
    _transferCurrentChunk = null;
    _transferTotalChunks = null;

    final success = result.fold(
      (_) {
        _error = null;
        LoggerService.info('✓ DOWNLOAD CONCLUÍDO COM SUCESSO!');
        return true;
      },
      (failure) {
        _error =
            'Falha ao baixar backup após ${SocketConfig.maxRetries} tentativas: $failure';
        LoggerService.error('✗ FALHA NO DOWNLOAD: $_error');
        LoggerService.error('Failure details: $failure');
        return false;
      },
    );

    if (success) {
      final downloadedFile = File(outputFilePath);
      if (!await downloadedFile.exists()) {
        _error =
            'Arquivo baixado não encontrado após transferência: $outputFilePath';
        LoggerService.error('✗ $_error');
        _isTransferring = false;
        notifyListeners();
        return false;
      }
      final downloadedSize = await downloadedFile.length();
      if (downloadedSize == 0) {
        _error =
            'Arquivo baixado está vazio (0 bytes). Não é possível enviar para '
            'destinos. Verifique o backup no servidor.';
        LoggerService.error('✗ $_error');
        _isTransferring = false;
        notifyListeners();
        return false;
      }
      LoggerService.info(
        'Arquivo baixado verificado: $outputFilePath ($downloadedSize bytes)',
      );

      try {
        LoggerService.info('Limpando staging do servidor...');
        await _transferStagingService.cleanupStaging(scheduleId);
        LoggerService.info('✓ Staging limpo');
      } on Object catch (e) {
        LoggerService.warning('Erro ao limpar staging (não crítico): $e');
      }

      if (linkedIds.isNotEmpty) {
        LoggerService.info('===== INICIANDO UPLOAD PARA DESTINOS =====');
        LoggerService.info('Arquivo local: $outputFilePath');
        LoggerService.info('Quantidade de destinos: ${linkedIds.length}');

        _isUploadingToRemotes = true;
        _uploadError = null;
        notifyListeners();

        final errors = <String>[];
        var completedUploads = 0;

        for (final id in linkedIds) {
          LoggerService.info('--- Processando destino: $id ---');

          final uploadProgress = linkedIds.isNotEmpty
              ? completedUploads / linkedIds.length
              : 0.0;
          onTransferProgress?.call(
            'Enviando para destinos',
            'Processando destino ${completedUploads + 1} de ${linkedIds.length}',
            uploadProgress,
          );

          final destResult = await _destinationRepository.getById(id);

          final destination = destResult.fold(
            (dest) {
              LoggerService.info(
                'Destino carregado: ${dest.name} (tipo: ${dest.type.name})',
              );
              return dest;
            },
            (failure) {
              final errMsg = 'Destino $id não encontrado';
              LoggerService.error(errMsg);
              errors.add(errMsg);
              return null;
            },
          );

          if (destination == null) {
            LoggerService.warning('Pulando destino $id (não encontrado)');
            completedUploads++;
            continue;
          }

          LoggerService.info('Enviando para: ${destination.name}');
          onTransferProgress?.call(
            'Enviando para ${destination.name}',
            'Iniciando upload...',
            uploadProgress,
          );

          final sendResult = await _sendFileToDestinationService.sendFile(
            localFilePath: outputFilePath,
            destination: destination,
            onProgress: (uploadProgressValue) {
              final baseProgress = completedUploads / linkedIds.length;
              final destinationProgress =
                  (1 / linkedIds.length) * uploadProgressValue;
              final totalProgress = baseProgress + destinationProgress;

              onTransferProgress?.call(
                'Enviando para ${destination.name}',
                '${(uploadProgressValue * 100).toStringAsFixed(1)}%',
                totalProgress,
              );
            },
          );

          sendResult.fold(
            (_) {
              LoggerService.info('✓ Upload concluído: ${destination.name}');
              completedUploads++;
              final finalProgress = completedUploads / linkedIds.length;
              onTransferProgress?.call(
                'Enviando para ${destination.name}',
                'Concluído',
                finalProgress,
              );
            },
            (failure) {
              final errMsg = '${destination.name}: $failure';
              LoggerService.error('✗ Erro no upload: $errMsg');
              errors.add(errMsg);
            },
          );
        }

        _isUploadingToRemotes = false;
        _uploadError = errors.isEmpty ? null : errors.join('; ');
        notifyListeners();

        if (errors.isEmpty) {
          LoggerService.info('✓ TODOS OS UPLOADS CONCLUÍDOS COM SUCESSO!');
        } else {
          LoggerService.warning(
            '⚠ Uploads concluídos com erros: $_uploadError',
          );
        }

        if (tempPathForCleanup != null && errors.isEmpty) {
          LoggerService.info('===== LIMPANDO ARQUIVO TEMPORÁRIO =====');
          LoggerService.info('TempPath: $tempPathForCleanup');
          try {
            final tempFile = File(outputFilePath);
            if (await tempFile.exists()) {
              await tempFile.delete();
              LoggerService.info(
                '✓ Arquivo temporário removido: $outputFilePath',
              );
            } else {
              LoggerService.warning(
                'Arquivo temporário não encontrado (pode já ter sido removido)',
              );
            }
          } on Object catch (e) {
            LoggerService.warning(
              'Não foi possível remover arquivo temporário: $e',
            );
          }
        } else {
          if (tempPathForCleanup != null) {
            LoggerService.info(
              'Arquivo temporário PRESERVADO (houve erros no upload)',
            );
          }
        }
      } else {
        LoggerService.info('Nenhum destino vinculado, pulando upload');
      }
    }

    LoggerService.info('===== FIM DA TRANSFERÊNCIA =====');
    LoggerService.info('Resultado final: ${success ? "SUCESSO" : "FALHA"}');

    notifyListeners();
    return success;
  }
}

class FileTransferHistoryEntry {
  const FileTransferHistoryEntry({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.status,
    required this.sourcePath,
    required this.destinationPath,
    this.completedAt,
    this.errorMessage,
  });

  final String id;
  final String fileName;
  final int fileSize;
  final String status;
  final DateTime? completedAt;
  final String sourcePath;
  final String destinationPath;
  final String? errorMessage;
}
