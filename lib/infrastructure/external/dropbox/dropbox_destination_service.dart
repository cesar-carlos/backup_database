import 'dart:io';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_dropbox_destination_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class DropboxDestinationService implements IDropboxDestinationService {
  DropboxDestinationService(this._authService);
  final DropboxAuthService _authService;
  Dio? _cachedDio;
  String? _cachedAccessToken;

  @override
  Future<rd.Result<DropboxUploadResult>> upload({
    required String sourceFilePath,
    required DropboxDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        return rd.Failure(
          FileSystemFailure(
            message: 'Arquivo de origem não encontrado: $sourceFilePath',
          ),
        );
      }

      final mainFolderPath = config.folderPath.isEmpty
          ? '/${config.folderName}'
          : '${config.folderPath}/${config.folderName}';

      final mainFolderResult = await _getOrCreateFolder(mainFolderPath);
      if (mainFolderResult.isError()) {
        return rd.Failure(mainFolderResult.exceptionOrNull()!);
      }

      final dateFolder = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dateFolderPath = '$mainFolderPath/$dateFolder';
      final dateFolderResult = await _getOrCreateFolder(dateFolderPath);
      if (dateFolderResult.isError()) {
        return rd.Failure(dateFolderResult.exceptionOrNull()!);
      }

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final fileSize = await sourceFile.length();
      final filePath = '$dateFolderPath/$fileName';

      await _deleteFileIfExists(filePath);

      final useResumableUpload =
          fileSize >= AppConstants.dropboxSimpleUploadLimit;

      Exception? lastError;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          final result = await _executeWithTokenRefresh(() async {
            final dioResult = await _getAuthenticatedDio();
            if (dioResult.isError()) {
              throw dioResult.exceptionOrNull()!;
            }

            final dio = dioResult.getOrNull()!;

            final uploadResult = useResumableUpload
                ? await _uploadResumable(dio, sourceFile, filePath, fileSize)
                : await _uploadSimple(dio, sourceFile, filePath, fileSize);

            if (uploadResult.containsKey('size')) {
              final remoteSize = uploadResult['size'] as int;
              if (remoteSize != fileSize) {
                try {
                  await dio.post(
                    '/2/files/delete_v2',
                    data: {'path': filePath},
                  );
                } on Object catch (e, s) {
                  LoggerService.error(
                    'Failed to delete corrupted file from Dropbox: $filePath',
                    e,
                    s,
                  );
                }

                throw Exception(
                  'Arquivo corrompido no Dropbox. '
                  'Local: $fileSize, Remoto: $remoteSize',
                );
              }
            }

            return uploadResult;
          });

          stopwatch.stop();

          return rd.Success(
            DropboxUploadResult(
              fileId: result['id'] as String,
              fileName: fileName,
              fileSize: fileSize,
              duration: stopwatch.elapsed,
            ),
          );
        } on Object catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());

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
        DropboxFailure(
          message: _getDropboxErrorMessage(lastError),
          originalError: lastError,
        ),
      );
    } on Object catch (e) {
      stopwatch.stop();
      return rd.Failure(
        DropboxFailure(message: _getDropboxErrorMessage(e), originalError: e),
      );
    }
  }

  Future<Map<String, dynamic>> _uploadSimple(
    Dio dio,
    File sourceFile,
    String filePath,
    int fileSize,
  ) async {
    final contentDio = Dio(
      BaseOptions(
        baseUrl: AppConstants.dropboxContentBaseUrl,
        connectTimeout: AppConstants.httpTimeout,
        receiveTimeout: AppConstants.httpTimeout,
        headers: dio.options.headers,
      ),
    );

    try {
      final response = await contentDio.post(
        '/2/files/upload',
        data: await sourceFile.readAsBytes(),
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Dropbox-API-Arg':
                '{"path": "$filePath", "mode": "add", "autorename": true}',
          },
        ),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final errorData = e.response?.data as Map<String, dynamic>?;
        final error = errorData?['error'] as Map<String, dynamic>?;
        final errorTag = error?['.tag'] as String?;

        if (errorTag == 'path/conflict') {
          final response = await contentDio.post(
            '/2/files/upload',
            data: await sourceFile.readAsBytes(),
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Dropbox-API-Arg': '{"path": "$filePath", "mode": "overwrite"}',
              },
            ),
          );

          return response.data as Map<String, dynamic>;
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _uploadResumable(
    Dio dio,
    File sourceFile,
    String filePath,
    int fileSize,
  ) async {
    const chunkSize = 4 * 1024 * 1024;
    final totalChunks = (fileSize / chunkSize).ceil();

    final contentDio = Dio(
      BaseOptions(
        baseUrl: AppConstants.dropboxContentBaseUrl,
        connectTimeout: AppConstants.httpTimeout,
        receiveTimeout: AppConstants.httpTimeout,
        headers: dio.options.headers,
      ),
    );

    String? sessionId;
    var offset = 0;

    final fileStream = sourceFile.openRead();

    for (var chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
      final chunk = await fileStream.take(chunkSize).toList();
      final chunkData = chunk.expand((list) => list).toList();

      if (chunkIndex == 0) {
        final response = await contentDio.post(
          '/2/files/upload_session/start',
          data: chunkData,
          options: Options(
            headers: {
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': '{"close": false}',
            },
          ),
        );

        final data = response.data as Map<String, dynamic>;
        sessionId = data['session_id'] as String;
        offset = chunkData.length;
      } else if (chunkIndex < totalChunks - 1) {
        await contentDio.post(
          '/2/files/upload_session/append_v2',
          data: chunkData,
          options: Options(
            headers: {
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg':
                  '{"cursor": {"session_id": "$sessionId", "offset": $offset}, "close": false}',
            },
          ),
        );

        offset += chunkData.length;
      } else {
        try {
          final response = await contentDio.post(
            '/2/files/upload_session/finish',
            data: chunkData,
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Dropbox-API-Arg':
                    '{"cursor": {"session_id": "$sessionId", "offset": $offset}, "commit": {"path": "$filePath", "mode": "add", "autorename": true}}',
              },
            ),
          );

          return response.data as Map<String, dynamic>;
        } on DioException catch (e) {
          if (e.response?.statusCode == 409) {
            final errorData = e.response?.data as Map<String, dynamic>?;
            final error = errorData?['error'] as Map<String, dynamic>?;
            final errorTag = error?['.tag'] as String?;

            if (errorTag == 'path/conflict') {
              final response = await contentDio.post(
                '/2/files/upload_session/finish',
                data: chunkData,
                options: Options(
                  headers: {
                    'Content-Type': 'application/octet-stream',
                    'Dropbox-API-Arg':
                        '{"cursor": {"session_id": "$sessionId", "offset": $offset}, "commit": {"path": "$filePath", "mode": "overwrite"}}',
                  },
                ),
              );

              return response.data as Map<String, dynamic>;
            }
          }
          rethrow;
        }
      }
    }

    throw Exception('Erro no upload resumável');
  }

  String _getDropboxErrorMessage(dynamic e) {
    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
      return 'Sessão do Dropbox expirada.\n'
          'Faça login novamente nas configurações.';
    } else if (errorStr.contains('403') || errorStr.contains('forbidden')) {
      return 'Sem permissão para acessar o Dropbox.\n'
          'Verifique se as permissões foram concedidas.';
    } else if (errorStr.contains('409') || errorStr.contains('conflict')) {
      return 'Arquivo ou pasta já existe no Dropbox.\n'
          'O sistema tentará sobrescrever o arquivo automaticamente na próxima tentativa.';
    } else if (errorStr.contains('507') ||
        errorStr.contains('insufficient_storage')) {
      return 'Limite de armazenamento do Dropbox atingido.\n'
          'Libere espaço ou faça upgrade do plano.';
    } else if (errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return 'Erro de conexão com o Dropbox.\n'
          'Verifique sua conexão com a internet.';
    } else if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao enviar para o Dropbox.\n'
          'Para arquivos grandes, o upload pode levar vários minutos.\n'
          'Tente novamente ou verifique sua conexão.';
    }

    return 'Erro no upload para o Dropbox após várias tentativas.\n'
        'Detalhes: $e';
  }

  Future<rd.Result<void>> _getOrCreateFolder(String folderPath) async {
    try {
      final dioResult = await _getAuthenticatedDio();
      if (dioResult.isError()) {
        return rd.Failure(dioResult.exceptionOrNull()!);
      }

      final dio = dioResult.getOrNull()!;

      try {
        final response = await dio.post(
          '/2/files/get_metadata',
          data: {'path': folderPath},
        );

        final metadata = response.data as Map<String, dynamic>?;
        final tag = metadata?['.tag'] as String?;

        if (tag == 'folder') {
          return const rd.Success(());
        } else if (tag == 'file') {
          return rd.Failure(
            DropboxFailure(
              message:
                  'Caminho existe mas é um arquivo, não uma pasta: $folderPath',
            ),
          );
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          final errorData = e.response?.data as Map<String, dynamic>?;
          final error = errorData?['error'] as Map<String, dynamic>?;
          final errorTag = error?['.tag'] as String?;

          if (errorTag != 'path_lookup/not_found') {
            rethrow;
          }
        } else if (e.response?.statusCode == 409) {
          final errorData = e.response?.data as Map<String, dynamic>?;
          final error = errorData?['error'] as Map<String, dynamic>?;
          final errorTag = error?['.tag'] as String?;

          if (errorTag == 'path/conflict' ||
              errorTag == 'path/conflict/folder') {
            return const rd.Success(());
          } else if (errorTag == 'path/conflict/file') {
            return rd.Failure(
              DropboxFailure(
                message:
                    'Caminho existe mas é um arquivo, não uma pasta: $folderPath',
              ),
            );
          } else {
            return const rd.Success(());
          }
        } else if (e.response?.statusCode == 401) {
          _cachedDio = null;
          _cachedAccessToken = null;
          final refreshResult = await _authService.signInSilently();
          if (refreshResult.isError()) {
            return rd.Failure(
              DropboxFailure(
                message:
                    'Sessão expirada. Faça login novamente nas configurações.',
                originalError: e,
              ),
            );
          }
          return await _getOrCreateFolder(folderPath);
        } else {
          return rd.Failure(
            DropboxFailure(
              message: 'Erro ao verificar pasta: ${e.response?.statusCode}',
              originalError: e,
            ),
          );
        }
      }

      try {
        await dio.post(
          '/2/files/create_folder_v2',
          data: {'path': folderPath, 'autorename': false},
        );
        return const rd.Success(());
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          final errorData = e.response?.data as Map<String, dynamic>?;
          final error = errorData?['error'] as Map<String, dynamic>?;
          final errorTag = error?['.tag'] as String?;

          if (errorTag == 'path/conflict' ||
              errorTag == 'path/conflict/folder' ||
              errorTag == 'path/conflict/file') {
            return const rd.Success(());
          }
        }

        if (e.response?.statusCode == 401) {
          _cachedDio = null;
          _cachedAccessToken = null;
          final refreshResult = await _authService.signInSilently();
          if (refreshResult.isError()) {
            return rd.Failure(
              DropboxFailure(
                message:
                    'Sessão expirada. Faça login novamente nas configurações.',
                originalError: e,
              ),
            );
          }
          return await _getOrCreateFolder(folderPath);
        }

        return rd.Failure(
          DropboxFailure(
            message: 'Erro ao criar pasta: ${e.response?.statusCode}',
            originalError: e,
          ),
        );
      }
    } on Object catch (e) {
      if (e is DropboxFailure) {
        return rd.Failure(e);
      }

      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('409') || errorStr.contains('conflict')) {
        return const rd.Success(());
      }

      return rd.Failure(
        DropboxFailure(
          message: 'Erro inesperado ao criar pasta: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<void> _deleteFileIfExists(String filePath) async {
    try {
      final dioResult = await _getAuthenticatedDio();
      if (dioResult.isError()) {
        return;
      }

      final dio = dioResult.getOrNull()!;

      try {
        await dio.post('/2/files/delete_v2', data: {'path': filePath});
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          final errorData = e.response?.data as Map<String, dynamic>?;
          final error = errorData?['error'] as Map<String, dynamic>?;
          final errorTag = error?['.tag'] as String?;

          if (errorTag == 'path_lookup/not_found' ||
              errorTag == 'path/conflict' ||
              errorTag == 'path/conflict/file' ||
              errorTag == 'path/conflict/folder') {
            return;
          }
        } else if (e.response?.statusCode == 404) {
          final errorData = e.response?.data as Map<String, dynamic>?;
          final error = errorData?['error'] as Map<String, dynamic>?;
          final errorTag = error?['.tag'] as String?;

          if (errorTag == 'path_lookup/not_found') {
            return;
          }
        }
      }
    } on Object catch (e, s) {
      LoggerService.error('Failed to delete file if exists: $filePath', e, s);
    }
  }

  @override
  Future<rd.Result<bool>> testConnection(
    DropboxDestinationConfig config,
  ) async {
    try {
      final dioResult = await _getAuthenticatedDio();
      if (dioResult.isError()) {
        return rd.Failure(dioResult.exceptionOrNull()!);
      }

      final dio = dioResult.getOrNull()!;
      final mainFolderPath = config.folderPath.isEmpty
          ? '/${config.folderName}'
          : '${config.folderPath}/${config.folderName}';

      await _executeWithTokenRefresh(() async {
        final response = await dio.post(
          '/2/files/get_metadata',
          data: {'path': mainFolderPath},
        );
        return response.data;
      });

      return const rd.Success(true);
    } on Object catch (e, s) {
      LoggerService.error('Erro ao testar conexão com Dropbox', e, s);
      return rd.Failure(
        DropboxFailure(
          message: _getDropboxErrorMessage(e),
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<int>> cleanOldBackups({
    required DropboxDestinationConfig config,
  }) async {
    try {
      final dioResult = await _getAuthenticatedDio();
      if (dioResult.isError()) {
        return rd.Failure(dioResult.exceptionOrNull()!);
      }

      final mainFolderPath = config.folderPath.isEmpty
          ? '/${config.folderName}'
          : '${config.folderPath}/${config.folderName}';

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      final dio = dioResult.getOrNull()!;

      final folders = await _executeWithTokenRefresh(() async {
        final response = await dio.post(
          '/2/files/list_folder',
          data: {'path': mainFolderPath},
        );

        final data = response.data as Map<String, dynamic>;
        return data['entries'] as List<dynamic>? ?? [];
      });

      var deletedCount = 0;
      for (final folder in folders) {
        final folderData = folder as Map<String, dynamic>;
        final folderName = folderData['name'] as String?;
        final folderPath =
            folderData['path_display'] as String? ??
            folderData['path_lower'] as String?;

        if (folderName == null || folderPath == null) continue;

        try {
          final folderDate = DateFormat('yyyy-MM-dd').parse(folderName);
          if (folderDate.isBefore(cutoffDate)) {
            await _executeWithTokenRefresh(() async {
              await dio.post('/2/files/delete_v2', data: {'path': folderPath});
            });
            deletedCount++;
          }
        } on Object catch (e, s) {
          LoggerService.error(
            'Failed to delete old backup folder: $folderPath',
            e,
            s,
          );
        }
      }

      return rd.Success(deletedCount);
    } on Object catch (e) {
      return rd.Failure(
        DropboxFailure(
          message: 'Erro ao limpar backups Dropbox: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<Dio>> _getAuthenticatedDio() async {
    try {
      final authResult = await _authService.signInSilently();
      if (authResult.isError()) {
        final newAuthResult = await _authService.signIn();
        if (newAuthResult.isError()) {
          return rd.Failure(newAuthResult.exceptionOrNull()!);
        }
        final token = newAuthResult.getOrNull()!.accessToken;
        _cachedDio = _createDio(token);
        _cachedAccessToken = token;
        return rd.Success(_cachedDio!);
      }

      final token = authResult.getOrNull()!.accessToken;

      if (_cachedAccessToken != token) {
        _cachedDio = _createDio(token);
        _cachedAccessToken = token;
      }

      return rd.Success(_cachedDio!);
    } on Object catch (e) {
      return rd.Failure(
        DropboxFailure(
          message: 'Erro ao obter cliente autenticado: $e',
          originalError: e,
        ),
      );
    }
  }

  Dio _createDio(String accessToken) {
    return Dio(
      BaseOptions(
        baseUrl: AppConstants.dropboxApiBaseUrl,
        connectTimeout: AppConstants.httpTimeout,
        receiveTimeout: AppConstants.httpTimeout,
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
    );
  }

  Future<T> _executeWithTokenRefresh<T>(Future<T> Function() operation) async {
    var attempts = 0;
    const maxAttempts = 2;

    while (attempts < maxAttempts) {
      try {
        return await operation();
      } on Object catch (e) {
        var is401 = false;

        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          is401 = statusCode == 401;
        }

        final errorStr = e.toString().toLowerCase();
        is401 =
            is401 ||
            errorStr.contains('401') ||
            errorStr.contains('unauthorized') ||
            errorStr.contains('invalid authentication credentials');

        if (is401 && attempts < maxAttempts - 1) {
          _cachedDio = null;
          _cachedAccessToken = null;

          final refreshResult = await _authService.signInSilently();
          if (refreshResult.isError()) {
            throw DropboxFailure(
              message:
                  'Sessão expirada. Faça login novamente nas configurações.',
              originalError: e,
            );
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
