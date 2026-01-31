import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/nextcloud_failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_webdav_utils.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class NextcloudUploadResult {
  const NextcloudUploadResult({
    required this.fileName,
    required this.fileSize,
    required this.duration,
  });
  final String fileName;
  final int fileSize;
  final Duration duration;
}

class NextcloudDestinationService {
  Future<rd.Result<NextcloudUploadResult>> upload({
    required String sourceFilePath,
    required NextcloudDestinationConfig config,
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

      final password = EncryptionService.decrypt(config.appPassword);

      final dio = _createDio(config: config, password: password);

      final baseFolderPath = _buildBaseFolderPath(
        remotePath: config.remotePath,
        folderName: config.folderName,
      );

      final dateFolderName = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dateFolderPath = _joinRemote(baseFolderPath, dateFolderName);

      final fileName = customFileName ?? p.basename(sourceFilePath);
      final fileSize = await sourceFile.length();
      final remoteFilePath = _joinRemote(dateFolderPath, fileName);

      Exception? lastError;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          await _ensureFolderExists(
            dio: dio,
            config: config,
            path: baseFolderPath,
          );
          await _ensureFolderExists(
            dio: dio,
            config: config,
            path: dateFolderPath,
          );

          final uploadUrl = NextcloudWebdavUtils.buildDavUrl(
            serverUrl: config.serverUrl,
            username: config.username,
            path: remoteFilePath,
          );

          final response = await dio.putUri(
            uploadUrl,
            data: sourceFile.openRead(),
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Length': fileSize,
              },
            ),
          );

          if (response.statusCode != null &&
              response.statusCode! >= 200 &&
              response.statusCode! < 300) {
            // Validação de Integridade via HEAD
            try {
              final headResponse = await dio.headUri(uploadUrl);
              final contentLengthStr = headResponse.headers.value(
                'content-length',
              );
              if (contentLengthStr != null) {
                final remoteSize = int.tryParse(contentLengthStr);
                if (remoteSize != null && remoteSize != fileSize) {
                  // Tentar apagar
                  try {
                    await dio.deleteUri(uploadUrl);
                  } on Object catch (_) {}

                  throw Exception(
                    'Arquivo corrompido no Nextcloud. '
                    'Local: $fileSize, Remoto: $remoteSize',
                  );
                }
              }
            } on Object catch (e) {
              LoggerService.warning(
                'Não foi possível validar integridade no Nextcloud: $e',
              );
              // Se falhar o HEAD, assumimos que pode ser problema de permissão ou rede
              // mas não necessariamente arquivo corrompido, então seguimos.
              // O ideal seria falhar, mas Nextcloud as vezes bloqueia HEAD/PROPFIND.
              // Mas aqui como acabamos de enviar, devemos ter acesso.
              if (e is Exception &&
                  e.toString().contains('Arquivo corrompido')) {
                rethrow;
              }
            }

            stopwatch.stop();
            return rd.Success(
              NextcloudUploadResult(
                fileName: fileName,
                fileSize: fileSize,
                duration: stopwatch.elapsed,
              ),
            );
          }

          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
          );
        } on Object catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 5));
          }
        }
      }

      stopwatch.stop();
      return rd.Failure(
        NextcloudFailure(
          message: _getNextcloudErrorMessage(lastError),
          originalError: lastError,
        ),
      );
    } on Object catch (e) {
      stopwatch.stop();
      return rd.Failure(
        NextcloudFailure(
          message: _getNextcloudErrorMessage(e),
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<bool>> testConnection(
    NextcloudDestinationConfig config,
  ) async {
    try {
      final password = EncryptionService.decrypt(config.appPassword);
      final dio = _createDio(config: config, password: password);

      final testUrl = NextcloudWebdavUtils.buildDavUrl(
        serverUrl: config.serverUrl,
        username: config.username,
        path: '/',
      );

      final response = await dio.requestUri(
        testUrl,
        options: Options(method: 'PROPFIND', headers: {'Depth': '0'}),
      );

      final statusCode = response.statusCode;
      if (statusCode != null && (statusCode == 200 || statusCode == 207)) {
        return const rd.Success(true);
      }

      return const rd.Success(false);
    } on Object catch (e) {
      return rd.Failure(
        NextcloudFailure(
          message:
              'Erro ao testar conexão Nextcloud: ${_getNextcloudErrorMessage(e)}',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<int>> cleanOldBackups({
    required NextcloudDestinationConfig config,
  }) async {
    try {
      final password = EncryptionService.decrypt(config.appPassword);
      final dio = _createDio(config: config, password: password);

      final baseFolderPath = _buildBaseFolderPath(
        remotePath: config.remotePath,
        folderName: config.folderName,
      );

      final cutoffDate = DateTime.now().subtract(
        Duration(days: config.retentionDays),
      );

      final folders = await _listCollections(
        dio: dio,
        config: config,
        path: baseFolderPath,
      );

      var deletedCount = 0;
      for (final folderName in folders) {
        try {
          final folderDate = DateFormat('yyyy-MM-dd').parse(folderName);
          if (folderDate.isBefore(cutoffDate)) {
            final folderPath = _joinRemote(baseFolderPath, folderName);
            final deleteUrl = NextcloudWebdavUtils.buildDavUrl(
              serverUrl: config.serverUrl,
              username: config.username,
              path: folderPath,
            );

            await dio.deleteUri(deleteUrl);
            deletedCount++;
          }
        } on Object catch (_) {
          // Nome não é uma data válida, ignorar
        }
      }

      return rd.Success(deletedCount);
    } on Object catch (e) {
      return rd.Failure(
        NextcloudFailure(
          message: 'Erro ao limpar backups Nextcloud: $e',
          originalError: e,
        ),
      );
    }
  }

  Dio _createDio({
    required NextcloudDestinationConfig config,
    required String password,
  }) {
    // Nota: Tanto appPassword quanto userPassword usam Basic Auth no Nextcloud WebDAV.
    // O campo authMode é mantido para documentação e possível validação futura.
    // appPassword: Senha de aplicativo gerada no Nextcloud (recomendado para segurança)
    // userPassword: Senha do usuário (menos seguro, mas suportado)
    final base64Auth = base64Encode(
      utf8.encode('${config.username}:$password'),
    );

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
        headers: {'Authorization': 'Basic $base64Auth'},
      ),
    );

    if (config.allowInvalidCertificates) {
      final adapter = dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
          return client;
        };
      }
    }

    return dio;
  }

  String _buildBaseFolderPath({
    required String remotePath,
    required String folderName,
  }) {
    final normalizedRemote = _normalizeRemotePath(remotePath);
    if (normalizedRemote == '/') {
      return '/$folderName';
    }
    return _joinRemote(normalizedRemote, folderName);
  }

  String _normalizeRemotePath(String path) {
    return NextcloudWebdavUtils.normalizeRemotePath(path);
  }

  String _joinRemote(String left, String right) {
    final l = left.endsWith('/') ? left.substring(0, left.length - 1) : left;
    final r = right.startsWith('/') ? right.substring(1) : right;
    if (l.isEmpty) return '/$r';
    if (r.isEmpty) return l;
    return '$l/$r';
  }

  Uri _buildDavUrl({
    required String serverUrl,
    required String username,
    required String path,
  }) => NextcloudWebdavUtils.buildDavUrl(
    serverUrl: serverUrl,
    username: username,
    path: path,
  );

  Future<void> _ensureFolderExists({
    required Dio dio,
    required NextcloudDestinationConfig config,
    required String path,
  }) async {
    final url = _buildDavUrl(
      serverUrl: config.serverUrl,
      username: config.username,
      path: path,
    );

    try {
      await dio.requestUri(url, options: Options(method: 'MKCOL'));
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 405 || statusCode == 409) {
        // 405: já existe, 409: pode ocorrer dependendo do servidor; ignorar
        return;
      }
      rethrow;
    }
  }

  Future<List<String>> _listCollections({
    required Dio dio,
    required NextcloudDestinationConfig config,
    required String path,
  }) async {
    final url = _buildDavUrl(
      serverUrl: config.serverUrl,
      username: config.username,
      path: path,
    );

    const propfindBody = '''
<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype />
  </d:prop>
</d:propfind>
''';

    final response = await dio.requestUri(
      url,
      data: propfindBody,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1', 'Content-Type': 'application/xml'},
      ),
    );

    final data = response.data;
    final xmlStr = data is String ? data : data?.toString() ?? '';
    if (xmlStr.isEmpty) return const [];

    return NextcloudWebdavUtils.parseCollectionNamesFromPropfind(
      xmlStr: xmlStr,
      requestedPath: url.path,
    );
  }

  String _getNextcloudErrorMessage(dynamic e) {
    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
      return 'Credenciais inválidas ou sessão expirada.\n'
          'Verifique o usuário e o App Password.';
    }
    if (errorStr.contains('403') || errorStr.contains('forbidden')) {
      return 'Sem permissão para acessar o Nextcloud.\n'
          'Verifique as permissões do usuário.';
    }
    if (errorStr.contains('507') || errorStr.contains('insufficient')) {
      return 'Armazenamento insuficiente no Nextcloud.\n'
          'Libere espaço ou aumente a cota.';
    }
    if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao enviar para o Nextcloud.\n'
          'Tente novamente ou verifique sua conexão.';
    }
    if (errorStr.contains('certificate') || errorStr.contains('handshake')) {
      return 'Falha de certificado TLS.\n'
          'Se o servidor usa certificado self-signed, habilite a opção correspondente.';
    }
    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Erro de conexão com o Nextcloud.\n'
          'Verifique sua conexão e a URL do servidor.';
    }

    return 'Erro no Nextcloud após várias tentativas.\n'
        'Detalhes: $e';
  }
}
