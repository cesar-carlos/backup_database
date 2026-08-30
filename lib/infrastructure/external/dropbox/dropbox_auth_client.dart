import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/utils/http_error_helpers.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_auth_service.dart';
import 'package:dio/dio.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Single owner of the Dropbox API Dio + access-token cache.
class DropboxAuthClient {
  DropboxAuthClient(this._authService);
  final DropboxAuthService _authService;
  Dio? _cachedDio;
  String? _cachedAccessToken;

  Future<rd.Result<DropboxAuthResult>> signInSilently() {
    return _authService.signInSilently();
  }

  void invalidateCache() {
    _cachedDio = null;
    _cachedAccessToken = null;
  }

  Future<rd.Result<Dio>> getAuthenticatedDio() async {
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
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao obter cliente autenticado Dropbox',
        e,
        stackTrace,
      );
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

  Future<T> executeWithTokenRefresh<T>(Future<T> Function() operation) async {
    var attempts = 0;
    const maxAttempts = 2;

    while (attempts < maxAttempts) {
      try {
        return await operation();
      } on Object catch (e) {
        if (_isUnauthorizedError(e) && attempts < maxAttempts - 1) {
          invalidateCache();

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

    throw const DropboxFailure(
      message: 'Número máximo de tentativas excedido ao autenticar no Dropbox.',
    );
  }

  /// Verifica se a exceção representa um erro `401 Unauthorized`. Prioriza
  /// `DioException.response.statusCode` (tipo nativo) antes de cair na
  /// heurística por substring com word‑boundary (delegada a
  /// `HttpErrorHelpers.matchesUnauthorizedHeuristic`, compartilhada
  /// com `GoogleDriveDestinationService`).
  static bool _isUnauthorizedError(Object e) {
    if (e is DioException && e.response?.statusCode == 401) return true;
    return HttpErrorHelpers.matchesUnauthorizedHeuristic(
      e.toString().toLowerCase(),
    );
  }
}
