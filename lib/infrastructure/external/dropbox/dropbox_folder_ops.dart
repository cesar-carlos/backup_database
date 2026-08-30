import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_client.dart';
import 'package:dio/dio.dart';
import 'package:result_dart/result_dart.dart' as rd;

class DropboxFolderOps {
  DropboxFolderOps(this._authClient);
  final DropboxAuthClient _authClient;

  Future<rd.Result<void>> getOrCreateFolder(String folderPath) async {
    try {
      final dioResult = await _authClient.getAuthenticatedDio();
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
          _authClient.invalidateCache();
          final refreshResult = await _authClient.signInSilently();
          if (refreshResult.isError()) {
            return rd.Failure(
              DropboxFailure(
                message:
                    'Sessão expirada. Faça login novamente nas configurações.',
                originalError: e,
              ),
            );
          }
          return await getOrCreateFolder(folderPath);
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
          _authClient.invalidateCache();
          final refreshResult = await _authClient.signInSilently();
          if (refreshResult.isError()) {
            return rd.Failure(
              DropboxFailure(
                message:
                    'Sessão expirada. Faça login novamente nas configurações.',
                originalError: e,
              ),
            );
          }
          return await getOrCreateFolder(folderPath);
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

  Future<void> deleteFileIfExists(String filePath) async {
    try {
      final dioResult = await _authClient.getAuthenticatedDio();
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
      LoggerService.error(
        'Falha ao remover arquivo existente no Dropbox: $filePath',
        e,
        s,
      );
    }
  }
}
