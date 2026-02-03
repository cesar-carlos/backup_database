import 'dart:convert';
import 'dart:io' show Directory;

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

  /// Executa uma operação com retentativa e exponential backoff
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

        // Aguarda com exponential backoff antes da próxima tentativa
        LoggerService.info(
          'Retrying $name in ${delay.inSeconds}s '
          '(attempt ${attempt + 1}/$maxAttempts)',
        );

        await Future.delayed(delay);

        // Calcula próximo delay com exponential backoff
        final nextDelayMs = delay.inMilliseconds * backoffMultiplier;
        final nextDelay = Duration(milliseconds: nextDelayMs);
        // Usa o delay menor entre o calculado e o máximo
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
      } on Object catch (_) {
        // ignore persistence failure; transfer result already reported
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
        await destResult.fold(
          (destination) async {
            final sendResult = await _sendFileToDestinationService.sendFile(
              localFilePath: outputFilePath,
              destination: destination,
            );
            sendResult.fold(
              (_) {},
              (failure) {
                // ignore: noop_primitive_operations - add used for side effect
                errors.add('${destination.name}: ${failure.toString()}');
              },
            );
          },
          (_) async {
            errors.add('Destino $id não encontrado');
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
    String relativePath,
  ) async {
    if (!_connectionManager.isConnected) return false;

    var destDir = _outputPath.trim();
    if (destDir.isEmpty) {
      final defaultPath = await getDefaultOutputPath();
      if (defaultPath != null && defaultPath.isNotEmpty) {
        destDir = defaultPath;
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        destDir = p.join(appDir.path, _receivedBackupsSubdir);
      }
    }

    final dir = Directory(destDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final outputFilePath = p.join(destDir, p.basename(relativePath));

    _isTransferring = true;
    _error = null;
    _transferCurrentChunk = null;
    _transferTotalChunks = null;
    notifyListeners();

    final result = await _executeWithRetry(
      () => _connectionManager.requestFile(
        filePath: relativePath,
        outputPath: outputFilePath,
        scheduleId: scheduleId,
        onProgress: (currentChunk, totalChunks) {
          _transferCurrentChunk = currentChunk;
          _transferTotalChunks = totalChunks;
          notifyListeners();
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
        return true;
      },
      (failure) {
        _error =
            'Falha ao baixar backup após ${SocketConfig.maxRetries} tentativas: $failure';
        return false;
      },
    );

    if (success) {
      // Limpar arquivo do staging após download bem-sucedido
      try {
        await _transferStagingService.cleanupStaging(scheduleId);
      } on Object catch (e) {
        // Não falhar a operação se cleanup falhar, apenas logar
        // O cleanupOldBackups irá limpar arquivos órfãos posteriormente
      }

      final linkedIds = await getLinkedDestinationIds(scheduleId);
      if (linkedIds.isNotEmpty) {
        _isUploadingToRemotes = true;
        _uploadError = null;
        notifyListeners();

        final errors = <String>[];
        for (final id in linkedIds) {
          final destResult = await _destinationRepository.getById(id);
          await destResult.fold(
            (destination) async {
              final sendResult = await _sendFileToDestinationService.sendFile(
                localFilePath: outputFilePath,
                destination: destination,
              );
              sendResult.fold(
                (_) {},
                (e) {
                  // ignore: noop_primitive_operations - add used for side effect
                  errors.add('${destination.name}: ${e.toString()}');
                },
              );
            },
            (_) async {
              errors.add('Destino $id não encontrado');
            },
          );
        }

        _isUploadingToRemotes = false;
        _uploadError = errors.isEmpty ? null : errors.join('; ');
        notifyListeners();
      }
    }

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
