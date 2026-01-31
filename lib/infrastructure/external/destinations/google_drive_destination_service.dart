import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure.dart'
    hide GoogleDriveFailure;
import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class GoogleDriveDestinationConfig {
  const GoogleDriveDestinationConfig({
    required this.folderId,
    this.folderName = 'Backups',
    this.retentionDays = 30,
  });
  final String folderId;
  final String folderName;
  final int retentionDays;
}

class GoogleDriveUploadResult {
  const GoogleDriveUploadResult({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.duration,
  });
  final String fileId;
  final String fileName;
  final int fileSize;
  final Duration duration;
}

class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient(this.accessToken);
  final String accessToken;
  final http.Client _client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _client.send(request);
  }
}

class _AuthenticatedClientData {
  _AuthenticatedClientData({
    required this.client,
    required this.accessToken,
  });
  final AuthenticatedHttpClient client;
  final String accessToken;
}

class GoogleDriveDestinationService {
  GoogleDriveDestinationService(this._authService);
  final GoogleAuthService _authService;
  _AuthenticatedClientData? _cachedClientData;

  Future<rd.Result<GoogleDriveUploadResult>> upload({
    required String sourceFilePath,
    required GoogleDriveDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Enviando para Google Drive: ${config.folderName}');

      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Arquivo de origem não encontrado: $sourceFilePath',
          ),
        );
      }

      final mainFolderId = await _getOrCreateFolder(
        config.folderName,
        config.folderId,
      );

      final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dateFolderId = await _getOrCreateFolder(
        dateFolder,
        mainFolderId,
      );

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final fileSize = await sourceFile.length();

      const largeFileThreshold = 5 * 1024 * 1024;
      final useResumableUpload = fileSize > largeFileThreshold;

      if (useResumableUpload) {
        LoggerService.info(
          'Arquivo grande detectado (${_formatFileSize(fileSize)}). Usando upload resumável.',
        );
      }

      Exception? lastError;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          LoggerService.debug('Tentativa $attempt de $maxRetries');

          final result = await _executeWithTokenRefresh(() async {
            final clientResult = await _getAuthenticatedClient();
            if (clientResult.isError()) {
              throw clientResult.exceptionOrNull()!;
            }

            final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);

            final driveFile = drive.File()
              ..name = fileName
              ..parents = [dateFolderId];

            final media = drive.Media(
              sourceFile.openRead(),
              fileSize,
            );

            final uploadedFile = await driveApi.files.create(
              driveFile,
              uploadMedia: media,
              $fields: 'id, name, size',
            );

            if (uploadedFile.size != null) {
              final remoteSize = int.parse(uploadedFile.size!);
              if (remoteSize != fileSize) {
                try {
                  await driveApi.files.delete(uploadedFile.id!);
                } on Object catch (e) {
                  LoggerService.warning(
                    'Não foi possível remover arquivo corrompido: $e',
                  );
                }

                throw Exception(
                  'Arquivo corrompido no Google Drive. '
                  'Local: $fileSize, Remoto: $remoteSize',
                );
              }
            }

            return uploadedFile;
          });

          stopwatch.stop();

          LoggerService.info(
            'Upload Google Drive concluído: ${result.id} (${_formatFileSize(fileSize)} em ${stopwatch.elapsed.inSeconds}s)',
          );

          return rd.Success(
            GoogleDriveUploadResult(
              fileId: result.id!,
              fileName: fileName,
              fileSize: fileSize,
              duration: stopwatch.elapsed,
            ),
          );
        } on Object catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          LoggerService.warning('Tentativa $attempt falhou: $e');

          if (attempt < maxRetries) {
            final delay = useResumableUpload
                ? AppConstants.retryDelay * 2
                : AppConstants.retryDelay;
            await Future.delayed(delay);
          }
        }
      }

      stopwatch.stop();
      return rd.Failure(
        GoogleDriveFailure(
          message: _getGoogleDriveErrorMessage(lastError),
          originalError: lastError,
        ),
      );
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro no upload Google Drive', e, stackTrace);
      return rd.Failure(
        GoogleDriveFailure(
          message: _getGoogleDriveErrorMessage(e),
          originalError: e,
        ),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _getGoogleDriveErrorMessage(dynamic e) {
    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
      return 'Sessão do Google Drive expirada.\n'
          'Faça login novamente nas configurações.';
    } else if (errorStr.contains('403') || errorStr.contains('forbidden')) {
      return 'Sem permissão para acessar o Google Drive.\n'
          'Verifique se as permissões foram concedidas.';
    } else if (errorStr.contains('404') || errorStr.contains('not found')) {
      return 'Pasta de destino não encontrada no Google Drive.\n'
          'Verifique se a pasta ainda existe.';
    } else if (errorStr.contains('quota') || errorStr.contains('limit')) {
      return 'Limite de armazenamento do Google Drive atingido.\n'
          'Libere espaço ou faça upgrade do plano.';
    } else if (errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return 'Erro de conexão com o Google Drive.\n'
          'Verifique sua conexão com a internet.';
    } else if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao enviar para o Google Drive.\n'
          'Para arquivos grandes, o upload pode levar vários minutos.\n'
          'Tente novamente ou verifique sua conexão.';
    } else if (errorStr.contains('413') ||
        errorStr.contains('request entity too large')) {
      return 'Arquivo muito grande para upload direto.\n'
          'O Google Drive suporta arquivos de até 5TB, mas o upload pode demorar.';
    }

    return 'Erro no upload para o Google Drive após várias tentativas.\n'
        'Detalhes: $e';
  }

  Future<String> _getOrCreateFolder(
    String folderName,
    String parentId,
  ) async {
    return _executeWithTokenRefresh(() async {
      final clientResult = await _getAuthenticatedClient();
      if (clientResult.isError()) {
        throw clientResult.exceptionOrNull()!;
      }

      final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);

      final query =
          "name = '$folderName' and '$parentId' in parents and "
          "mimeType = 'application/vnd.google-apps.folder' and trashed = false";

      final existing = await driveApi.files.list(
        q: query,
        spaces: 'drive',
      );

      if (existing.files != null && existing.files!.isNotEmpty) {
        return existing.files!.first.id!;
      }

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId];

      final created = await driveApi.files.create(folder);
      return created.id!;
    });
  }

  Future<rd.Result<int>> cleanOldBackups({
    required GoogleDriveDestinationConfig config,
  }) async {
    try {
      LoggerService.info('Limpando backups antigos no Google Drive');

      final authResult = await _getAuthenticatedClient();
      if (authResult.isError()) {
        return rd.Failure(authResult.exceptionOrNull()!);
      }

      final mainFolderId = await _getOrCreateFolder(
        config.folderName,
        config.folderId,
      );

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      final folders = await _executeWithTokenRefresh(() async {
        final clientResult = await _getAuthenticatedClient();
        if (clientResult.isError()) {
          throw clientResult.exceptionOrNull()!;
        }

        final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
        final query =
            "'$mainFolderId' in parents and "
            "mimeType = 'application/vnd.google-apps.folder' and trashed = false";

        return driveApi.files.list(
          q: query,
          spaces: 'drive',
          $fields: 'files(id, name, createdTime)',
        );
      });

      var deletedCount = 0;
      for (final folder in folders.files ?? []) {
        try {
          final folderName = folder.name as String?;
          if (folderName == null || folderName.isEmpty) continue;
          final folderDate = DateFormat('yyyy-MM-dd').parse(folderName);
          if (folderDate.isBefore(cutoffDate)) {
            final folderId = folder.id as String?;
            if (folderId == null) continue;
            await _executeWithTokenRefresh(() async {
              final clientResult = await _getAuthenticatedClient();
              if (clientResult.isError()) {
                throw clientResult.exceptionOrNull()!;
              }

              final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
              await driveApi.files.delete(folderId);
            });
            deletedCount++;
            LoggerService.debug('Pasta deletada: ${folder.name}');
          }
        } on Object catch (e) {
          LoggerService.debug('Erro ao deletar pasta vazia: $e');
        }
      }

      LoggerService.info(
        '$deletedCount pastas antigas removidas do Google Drive',
      );
      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao limpar backups Google Drive',
        e,
        stackTrace,
      );
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao limpar backups Google Drive: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<List<drive.File>>> listBackups({
    required String folderId,
  }) async {
    try {
      final result = await _executeWithTokenRefresh(() async {
        final clientResult = await _getAuthenticatedClient();
        if (clientResult.isError()) {
          throw clientResult.exceptionOrNull()!;
        }

        final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
        final query = "'$folderId' in parents and trashed = false";

        return driveApi.files.list(
          q: query,
          spaces: 'drive',
          orderBy: 'modifiedTime desc',
          $fields: 'files(id, name, size, modifiedTime, mimeType)',
        );
      });

      return rd.Success(result.files ?? []);
    } on Object catch (e) {
      return rd.Failure(
        GoogleDriveFailure(message: 'Erro ao listar backups: $e'),
      );
    }
  }

  Future<rd.Result<_AuthenticatedClientData>> _getAuthenticatedClient() async {
    try {
      final authResult = await _authService.signInSilently();
      if (authResult.isError()) {
        LoggerService.debug('signInSilently falhou, tentando signIn');
        final newAuthResult = await _authService.signIn();
        if (newAuthResult.isError()) {
          return rd.Failure(newAuthResult.exceptionOrNull()!);
        }
        final token = newAuthResult.getOrNull()!.accessToken;
        _cachedClientData = _AuthenticatedClientData(
          client: AuthenticatedHttpClient(token),
          accessToken: token,
        );
        return rd.Success(_cachedClientData!);
      }

      final token = authResult.getOrNull()!.accessToken;

      if (_cachedClientData?.accessToken != token) {
        _cachedClientData = _AuthenticatedClientData(
          client: AuthenticatedHttpClient(token),
          accessToken: token,
        );
      }

      return rd.Success(_cachedClientData!);
    } on Object catch (e) {
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao obter cliente autenticado: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<T> _executeWithTokenRefresh<T>(Future<T> Function() operation) async {
    var attempts = 0;
    const maxAttempts = 2;

    while (attempts < maxAttempts) {
      try {
        return await operation();
      } on Object catch (e) {
        var is401 = false;

        try {
          if (e.toString().contains('DetailedApiRequestError')) {
            final errorStr = e.toString();
            if (errorStr.contains('status: 401') ||
                errorStr.contains('status:401')) {
              is401 = true;
            }
          }
        } on Object catch (_) {}

        final errorStr = e.toString().toLowerCase();
        is401 =
            is401 ||
            errorStr.contains('401') ||
            errorStr.contains('unauthorized') ||
            errorStr.contains('invalid authentication credentials');

        if (is401 && attempts < maxAttempts - 1) {
          LoggerService.warning('Erro 401 detectado, tentando renovar token');
          _cachedClientData = null;

          final refreshResult = await _authService.signInSilently();
          if (refreshResult.isError()) {
            LoggerService.debug(
              'signInSilently falhou após 401, tentando signIn',
            );
            final newAuthResult = await _authService.signIn();
            if (newAuthResult.isError()) {
              throw GoogleDriveFailure(
                message: 'Sessão expirada. Faça login novamente.',
                originalError: e,
              );
            }
          } else {
            LoggerService.info('Token renovado com sucesso após erro 401');
          }

          attempts++;
          continue;
        }

        rethrow;
      }
    }

    throw Exception('Número máximo de tentativas excedido');
  }
}
