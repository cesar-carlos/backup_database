import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/core/utils/http_error_helpers.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:result_dart/result_dart.dart' as rd;

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

class GoogleDriveClientSession {
  GoogleDriveClientSession({
    required this.client,
    required this.accessToken,
  });
  final AuthenticatedHttpClient client;
  final String accessToken;
}

/// Single owner of the Drive HTTP client + access-token cache.
class GoogleDriveAuthClient {
  GoogleDriveAuthClient(this._authService);
  final GoogleAuthService _authService;
  GoogleDriveClientSession? _cachedClientData;

  Future<rd.Result<GoogleDriveClientSession>> getAuthenticatedClient() async {
    try {
      final authResult = await _authService.signInSilently();
      if (authResult.isError()) {
        LoggerService.debug('signInSilently falhou, tentando signIn');
        final newAuthResult = await _authService.signIn();
        if (newAuthResult.isError()) {
          return rd.Failure(newAuthResult.exceptionOrNull()!);
        }
        final token = newAuthResult.getOrNull()!.accessToken;
        _cachedClientData = GoogleDriveClientSession(
          client: AuthenticatedHttpClient(token),
          accessToken: token,
        );
        return rd.Success(_cachedClientData!);
      }

      final token = authResult.getOrNull()!.accessToken;

      if (_cachedClientData?.accessToken != token) {
        _cachedClientData = GoogleDriveClientSession(
          client: AuthenticatedHttpClient(token),
          accessToken: token,
        );
      }

      return rd.Success(_cachedClientData!);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao obter cliente autenticado Google Drive',
        e,
        stackTrace,
      );
      return rd.Failure(
        GoogleDriveFailure(
          message: 'Erro ao obter cliente autenticado: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<T> executeWithTokenRefresh<T>(Future<T> Function() operation) async {
    var attempts = 0;
    const maxAttempts = 2;

    while (attempts < maxAttempts) {
      try {
        return await operation();
      } on Object catch (e) {
        if (_isUnauthorizedError(e) && attempts < maxAttempts - 1) {
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

    throw const GoogleDriveFailure(
      message:
          'Número máximo de tentativas excedido ao autenticar no Google Drive.',
    );
  }

  /// Verifica se a exceção representa um erro `401 Unauthorized`. Prioriza
  /// o tipo nativo (`drive.DetailedApiRequestError.status`) antes de cair
  /// na heurística por substring (delegada a
  /// `HttpErrorHelpers.matchesUnauthorizedHeuristic`, compartilhada
  /// com `DropboxDestinationService`).
  static bool _isUnauthorizedError(Object e) {
    if (e is drive.DetailedApiRequestError && e.status == 401) return true;
    return HttpErrorHelpers.matchesUnauthorizedHeuristic(
      e.toString().toLowerCase(),
    );
  }
}
