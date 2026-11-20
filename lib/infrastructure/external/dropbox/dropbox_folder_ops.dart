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
      await _authClient.executeWithTokenRefresh(() async {
        final dio = (await _authClient.getAuthenticatedDio()).getOrThrow();
        Future<void> verifyFolder() async {
          final response = await dio.post<dynamic>(
            '/2/files/get_metadata',
            data: {'path': folderPath},
          );
          final metadata = response.data;
          if (metadata is! Map || metadata['.tag'] != 'folder') {
            throw const DropboxFailure(
              message: 'O caminho Dropbox não foi confirmado como pasta.',
            );
          }
        }

        try {
          await verifyFolder();
          return;
        } on DioException catch (error) {
          final detail = _errorDetail(error);
          final path = detail?['path'];
          if (error.response?.statusCode != 409 ||
              detail?['.tag'] != 'path' ||
              path is! Map ||
              path['.tag'] != 'not_found') {
            rethrow;
          }
        }
        try {
          final response = await dio.post<dynamic>(
            '/2/files/create_folder_v2',
            data: {'path': folderPath, 'autorename': false},
          );
          final data = response.data;
          final metadata = data is Map ? data['metadata'] : null;
          if (metadata is! Map ||
              metadata['id'] is! String ||
              (metadata['id'] as String).isEmpty) {
            await verifyFolder();
          }
        } on DioException catch (error) {
          final detail = _errorDetail(error);
          final path = detail?['path'];
          final conflict = path is Map ? path['conflict'] : null;
          if (error.response?.statusCode != 409 ||
              detail?['.tag'] != 'path' ||
              path is! Map ||
              path['.tag'] != 'conflict' ||
              conflict is! Map ||
              conflict['.tag'] != 'folder') {
            rethrow;
          }
          // Another process may have created the folder after our lookup.
          await verifyFolder();
        }
      });
      return const rd.Success(());
    } on Object catch (error) {
      return rd.Failure(
        error is DropboxFailure
            ? error
            : DropboxFailure(
                message:
                    'Não foi possível confirmar a pasta de destino Dropbox.',
                originalError: error,
              ),
      );
    }
  }

  static Map<dynamic, dynamic>? _errorDetail(DioException error) {
    final data = error.response?.data;
    final detail = data is Map ? data['error'] : null;
    return detail is Map ? detail : null;
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
