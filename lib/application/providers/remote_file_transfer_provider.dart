import 'dart:convert';
import 'dart:io' show File;

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/domain/services/i_send_file_to_destination_service.dart';
import 'package:backup_database/infrastructure/datasources/daos/file_transfer_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
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
    this._sendFileToDestinationService,
    this._tempDirectoryService,
    this._machineSettings, {
    FileTransferDao? fileTransferDao,
  }) : _fileTransferDao = fileTransferDao;

  final ConnectionManager _connectionManager;
  final IBackupDestinationRepository _destinationRepository;
  final ISendFileToDestinationService _sendFileToDestinationService;
  final TempDirectoryService _tempDirectoryService;
  final IMachineSettingsRepository _machineSettings;
  final FileTransferDao? _fileTransferDao;

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

  /// Primeiro segmento de caminho após `remote/` — pasta no servidor (runId
  /// em execuções remotas ou `scheduleId` no layout legado).
  String? _remoteStagingDirectoryKey(String relativePath) {
    final norm = p.normalize(relativePath).replaceAll(r'\', '/');
    final segs = norm.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.length >= 2 && segs[0] == 'remote') {
      return segs[1];
    }
    return null;
  }

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

  Future<String?> getDefaultOutputPath() async =>
      _machineSettings.getReceivedBackupsDefaultPath();

  Future<void> setDefaultOutputPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    await _machineSettings.setReceivedBackupsDefaultPath(trimmed);
  }

  Future<List<String>> getLinkedDestinationIds(String scheduleId) async {
    if (scheduleId.isEmpty) return [];
    final json = await _machineSettings.getScheduleTransferDestinationsJson();
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
    final json = await _machineSettings.getScheduleTransferDestinationsJson();
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
    await _machineSettings.setScheduleTransferDestinationsJson(
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
        _error = failure is Failure ? failure.message : failure.toString();
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
      } on Object catch (e, st) {
        LoggerService.debug(
          'RemoteFileTransferProvider: insertTransfer history failed: $e',
          e,
          st,
        );
      }
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

  Future<bool> transferCompletedBackupToClient(
    String scheduleId,
    String relativePath, {
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

    final linkedIds = await getLinkedDestinationIds(scheduleId);
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

    _isTransferring = true;
    _error = null;
    _transferCurrentChunk = null;
    _transferTotalChunks = null;
    notifyListeners();

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
        runId: runId,
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
        LoggerService.info('Download de backup concluído: $outputFilePath');
        return true;
      },
      (failure) {
        _error =
            'Falha ao baixar backup após ${SocketConfig.maxRetries} tentativas: $failure';
        LoggerService.error('Falha no download de backup', failure);
        return false;
      },
    );

    if (success) {
      final downloadedFile = File(outputFilePath);
      if (!await downloadedFile.exists()) {
        _error =
            'Arquivo baixado não encontrado após transferência: $outputFilePath';
        LoggerService.error(_error!);
        _isTransferring = false;
        notifyListeners();
        return false;
      }
      final downloadedSize = await downloadedFile.length();
      if (downloadedSize == 0) {
        _error =
            'Arquivo baixado está vazio (0 bytes). Não é possível enviar para '
            'destinos. Verifique o backup no servidor.';
        LoggerService.error(_error!);
        _isTransferring = false;
        notifyListeners();
        return false;
      }
      LoggerService.info(
        'Arquivo baixado verificado: $outputFilePath ($downloadedSize bytes)',
      );

      final stagingKey = _remoteStagingDirectoryKey(relativePath);
      if (stagingKey != null) {
        final remoteCleanup = await _connectionManager.cleanupRemoteStaging(
          runId: stagingKey,
        );
        remoteCleanup.fold(
          (_) {
            LoggerService.debug('Limpeza do staging no servidor: $stagingKey');
          },
          (failure) {
            LoggerService.warning(
              'Falha ao solicitar limpeza do staging remoto (não crítico): $failure',
            );
          },
        );
      } else {
        LoggerService.debug(
          'Caminho relativo sem padrão remote/<chave>/; limpeza remota ignorada: '
          '$relativePath',
        );
      }

      var uploadHadErrors = false;
      if (linkedIds.isNotEmpty) {
        uploadHadErrors = await _uploadDownloadedFileToDestinations(
          outputFilePath: outputFilePath,
          linkedIds: linkedIds,
          onTransferProgress: onTransferProgress,
        );
      } else {
        LoggerService.debug('Nenhum destino vinculado, pulando upload');
      }

      // Política unificada: só remove o arquivo temporário quando não houve
      // erros (preserva para retry manual) ou quando não há destinos
      // vinculados (não há retry possível, então é seguro remover).
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

    notifyListeners();
    return success;
  }

  /// Faz upload do arquivo baixado para todos os destinos vinculados.
  /// Retorna `true` se houve algum erro (para preservar o arquivo temporário).
  Future<bool> _uploadDownloadedFileToDestinations({
    required String outputFilePath,
    required List<String> linkedIds,
    required TransferProgressCallback? onTransferProgress,
  }) async {
    LoggerService.info(
      'Iniciando upload para ${linkedIds.length} destinos vinculados',
    );

    _isUploadingToRemotes = true;
    _uploadError = null;
    notifyListeners();

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
          final errMsg = '${destination.name}: $failure';
          LoggerService.error('Erro no upload para ${destination.name}', failure);
          errors.add(errMsg);
        },
      );
    }

    _isUploadingToRemotes = false;
    _uploadError = errors.isEmpty ? null : errors.join('; ');
    notifyListeners();

    if (errors.isEmpty) {
      LoggerService.info('Todos os uploads concluídos com sucesso');
    } else {
      LoggerService.warning('Uploads concluídos com erros: $_uploadError');
    }
    return errors.isNotEmpty;
  }

  /// Remove o arquivo temporário com tratamento defensivo de erros.
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
