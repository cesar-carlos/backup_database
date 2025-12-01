import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:http/http.dart' as http;

import '../../../core/errors/failure.dart' hide GoogleDriveFailure;
import '../../../core/errors/google_drive_failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../core/constants/app_constants.dart';
import '../google/google_auth_service.dart';

class GoogleDriveDestinationConfig {
  final String folderId;
  final String folderName;
  final int retentionDays;

  const GoogleDriveDestinationConfig({
    required this.folderId,
    this.folderName = 'Backups',
    this.retentionDays = 30,
  });
}

class GoogleDriveUploadResult {
  final String fileId;
  final String fileName;
  final int fileSize;
  final Duration duration;

  const GoogleDriveUploadResult({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.duration,
  });
}

// Cliente HTTP autenticado
class AuthenticatedHttpClient extends http.BaseClient {
  final String accessToken;
  final http.Client _client = http.Client();

  AuthenticatedHttpClient(this.accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _client.send(request);
  }
}

// Helper para armazenar cliente autenticado
class _AuthenticatedClientData {
  final AuthenticatedHttpClient client;
  final String accessToken;

  _AuthenticatedClientData({
    required this.client,
    required this.accessToken,
  });
}

class GoogleDriveDestinationService {
  final GoogleAuthService _authService;
  _AuthenticatedClientData? _cachedClientData;

  GoogleDriveDestinationService(this._authService);

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

      // Obter cliente autenticado
      // Primeiro, criar ou obter a pasta principal "Backups"
      final mainFolderId = await _getOrCreateFolder(
        config.folderName,
        config.folderId,
      );

      // Depois, criar pasta de data dentro da pasta principal
      final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dateFolderId = await _getOrCreateFolder(
        dateFolder,
        mainFolderId,
      );

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final fileSize = await sourceFile.length();

      // Usar upload resumável para arquivos maiores que 5MB (recomendação do Google)
      const largeFileThreshold = 5 * 1024 * 1024; // 5MB
      final useResumableUpload = fileSize > largeFileThreshold;

      if (useResumableUpload) {
        LoggerService.info(
          'Arquivo grande detectado (${_formatFileSize(fileSize)}). Usando upload resumável.',
        );
      }

      // Upload com retry
      Exception? lastError;
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
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

            // O googleapis usa upload resumável automaticamente para arquivos grandes
            return await driveApi.files.create(
              driveFile,
              uploadMedia: media,
            );
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
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          LoggerService.warning('Tentativa $attempt falhou: $e');

          // Para arquivos grandes, aguardar mais tempo entre tentativas
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
    } catch (e, stackTrace) {
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
    } else if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Erro de conexão com o Google Drive.\n'
          'Verifique sua conexão com a internet.';
    } else if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao enviar para o Google Drive.\n'
          'Para arquivos grandes, o upload pode levar vários minutos.\n'
          'Tente novamente ou verifique sua conexão.';
    } else if (errorStr.contains('413') || errorStr.contains('request entity too large')) {
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
    return await _executeWithTokenRefresh(() async {
      final clientResult = await _getAuthenticatedClient();
      if (clientResult.isError()) {
        throw clientResult.exceptionOrNull()!;
      }

      final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);

      // Verificar se a pasta já existe
      final query = "name = '$folderName' and '$parentId' in parents and "
          "mimeType = 'application/vnd.google-apps.folder' and trashed = false";

      final existing = await driveApi.files.list(
        q: query,
        spaces: 'drive',
      );

      if (existing.files != null && existing.files!.isNotEmpty) {
        return existing.files!.first.id!;
      }

      // Criar nova pasta
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

      // Primeiro, obter a pasta principal "Backups"
      final mainFolderId = await _getOrCreateFolder(
        config.folderName,
        config.folderId,
      );

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      // Listar subpastas (pastas de data) dentro da pasta principal
      final folders = await _executeWithTokenRefresh(() async {
        final clientResult = await _getAuthenticatedClient();
        if (clientResult.isError()) {
          throw clientResult.exceptionOrNull()!;
        }

        final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
        final query = "'$mainFolderId' in parents and "
            "mimeType = 'application/vnd.google-apps.folder' and trashed = false";

        return await driveApi.files.list(
          q: query,
          spaces: 'drive',
          $fields: 'files(id, name, createdTime)',
        );
      });

      int deletedCount = 0;
      for (final folder in folders.files ?? []) {
        try {
          final folderDate = DateFormat('yyyy-MM-dd').parse(folder.name!);
          if (folderDate.isBefore(cutoffDate)) {
            await _executeWithTokenRefresh(() async {
              final clientResult = await _getAuthenticatedClient();
              if (clientResult.isError()) {
                throw clientResult.exceptionOrNull()!;
              }

              final driveApi = drive.DriveApi(clientResult.getOrNull()!.client);
              await driveApi.files.delete(folder.id!);
            });
            deletedCount++;
            LoggerService.debug('Pasta deletada: ${folder.name}');
          }
        } catch (e) {
          // Nome não é uma data válida, ignorar
        }
      }

      LoggerService.info(
        '$deletedCount pastas antigas removidas do Google Drive',
      );
      return rd.Success(deletedCount);
    } catch (e, stackTrace) {
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

        return await driveApi.files.list(
          q: query,
          spaces: 'drive',
          orderBy: 'modifiedTime desc',
          $fields: 'files(id, name, size, modifiedTime, mimeType)',
        );
      });

      return rd.Success(result.files ?? []);
    } catch (e) {
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
    } catch (e) {
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao obter cliente autenticado: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<T> _executeWithTokenRefresh<T>(Future<T> Function() operation) async {
    int attempts = 0;
    const maxAttempts = 2;

    while (attempts < maxAttempts) {
      try {
        return await operation();
      } catch (e) {
        bool is401 = false;
        
        // Verificar se é DetailedApiRequestError com status 401
        try {
          if (e.toString().contains('DetailedApiRequestError')) {
            final errorStr = e.toString();
            if (errorStr.contains('status: 401') || errorStr.contains('status:401')) {
              is401 = true;
            }
          }
        } catch (_) {
          // Ignorar erros na verificação
        }
        
        // Verificar outras formas de erro 401
        final errorStr = e.toString().toLowerCase();
        is401 = is401 ||
            errorStr.contains('401') ||
            errorStr.contains('unauthorized') ||
            errorStr.contains('invalid authentication credentials');

        if (is401 && attempts < maxAttempts - 1) {
          LoggerService.warning('Erro 401 detectado, tentando renovar token');
          _cachedClientData = null;

          final refreshResult = await _authService.signInSilently();
          if (refreshResult.isError()) {
            LoggerService.debug('signInSilently falhou após 401, tentando signIn');
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

