import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/providers/transfer/remote_file_destination_uploader.dart';
import 'package:backup_database/application/providers/transfer/remote_file_download_coordinator.dart';
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

export 'package:backup_database/application/providers/transfer/remote_file_destination_uploader.dart'
    show TransferProgressCallback;

class RemoteFileTransferProvider extends ChangeNotifier {
  RemoteFileTransferProvider(
    this._connectionManager,
    this._destinationRepository,
    this._sendFileToDestinationService,
    this._tempDirectoryService,
    this._machineSettings, {
    this._fileTransferDao,
  }) {
    _uploader = RemoteFileDestinationUploader(
      destinationRepository: _destinationRepository,
      sendFileToDestinationService: _sendFileToDestinationService,
      notifyListeners: notifyListeners,
      setUploading: (isUploading) => _isUploadingToRemotes = isUploading,
      setUploadError: (error) => _uploadError = error,
    );
    _download = RemoteFileDownloadCoordinator(
      connectionManager: _connectionManager,
      tempDirectoryService: _tempDirectoryService,
      uploader: _uploader,
      ui: RemoteFileTransferUiHooks(
        beginTransfer: () {
          _isTransferring = true;
          _error = null;
          _transferCurrentChunk = null;
          _transferTotalChunks = null;
          notifyListeners();
        },
        onChunkProgress: (currentChunk, totalChunks) {
          _transferCurrentChunk = currentChunk;
          _transferTotalChunks = totalChunks;
          notifyListeners();
        },
        endTransfer: ({String? error}) {
          _isTransferring = false;
          _transferCurrentChunk = null;
          _transferTotalChunks = null;
          _error = error;
        },
        notify: notifyListeners,
      ),
    );
  }

  final ConnectionManager _connectionManager;
  final IBackupDestinationRepository _destinationRepository;
  final ISendFileToDestinationService _sendFileToDestinationService;
  final TempDirectoryService _tempDirectoryService;
  final IMachineSettingsRepository _machineSettings;
  final FileTransferDao? _fileTransferDao;
  late final RemoteFileDestinationUploader _uploader;
  late final RemoteFileDownloadCoordinator _download;

  List<RemoteFileEntry> _files = [];
  RemoteFileEntry? _selectedFile;
  String _outputPath = '';
  bool _isLoading = false;
  bool _isTransferring = false;
  int? _transferCurrentChunk;
  int? _transferTotalChunks;
  List<FileTransferHistoryEntry> _transferHistory = [];
  String? _error;
  Set<String> _selectedDestinationIds = {};
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
    _selectedDestinationIds = Set<String>.from(ids);
    notifyListeners();
  }

  void toggleSelectedDestination(String id) {
    if (_selectedDestinationIds.contains(id)) {
      _selectedDestinationIds = {..._selectedDestinationIds}..remove(id);
    } else {
      _selectedDestinationIds = {..._selectedDestinationIds, id};
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
        _error = failureUserMessage(failure);
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

    final result = await _download.downloadFile(
      filePath: selected.path,
      outputPath: outputFilePath,
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
            'Falha ao baixar arquivo após ${SocketConfig.maxRetries} '
            'tentativas: ${failureUserMessage(failure)}';
        return false;
      },
    );

    if (_fileTransferDao != null) {
      try {
        final stagingKey = _remoteStagingDirectoryKey(selected.path);
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
            runId: Value(stagingKey),
          ),
        );
      } on Object catch (e, st) {
        LoggerService.debug(
          'RemoteFileTransferProvider: insertTransfer history failed: $e',
          e,
          st,
        );
      }
      unawaited(loadTransferHistory());
    }

    if (success && _selectedDestinationIds.isNotEmpty) {
      await _uploader.uploadToSelected(
        localFilePath: outputFilePath,
        destinationIds: _selectedDestinationIds,
      );
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
    final linkedIds = await getLinkedDestinationIds(scheduleId);
    return _download.transferCompletedBackupToClient(
      scheduleId: scheduleId,
      relativePath: relativePath,
      runId: runId,
      linkedIds: linkedIds,
      stagingDirectoryKey: _remoteStagingDirectoryKey,
      onTransferProgress: onTransferProgress,
    );
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
