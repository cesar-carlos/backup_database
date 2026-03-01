import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/constants/destination_retry_constants.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/nextcloud_failure.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/file_stream_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_webdav_utils.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class NextcloudDestinationService implements INextcloudDestinationService {
  static const _integrityReadBackAttempts = 2;
  static const _integrityReadBackDelay = Duration(seconds: 1);

  @override
  Future<rd.Result<NextcloudUploadResult>> upload({
    required String sourceFilePath,
    required NextcloudDestinationConfig config,
    String? customFileName,
    int maxRetries = 3,
    UploadProgressCallback? onProgress,
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
      final localSha256 = await FileHashUtils.computeSha256(sourceFile);
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
            data: chunkedFileStream(
              sourceFile,
              UploadChunkConstants.httpUploadChunkSize,
            ),
            onSendProgress: onProgress != null
                ? (sent, total) {
                    if (total > 0) {
                      onProgress(sent / total);
                    }
                  }
                : null,
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
            final integrityResult = await _validateUploadedFileIntegrity(
              dio: dio,
              uploadUrl: uploadUrl,
              fileSize: fileSize,
              localSha256: localSha256,
            );
            if (integrityResult.isError()) {
              final failure = integrityResult.exceptionOrNull()!;
              try {
                await dio.deleteUri(uploadUrl);
              } on Object catch (deleteError, s) {
                LoggerService.warning(
                  'Erro ao deletar arquivo inválido no Nextcloud',
                  deleteError,
                  s,
                );
              }
              throw failure;
            }

            stopwatch.stop();
            return rd.Success(
              NextcloudUploadResult(
                remotePath: remoteFilePath,
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
          LoggerService.warning(
            'Nextcloud: tentativa $attempt falhou: $e',
          );
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 5));
          }
        }
      }

      stopwatch.stop();
      if (lastError is NextcloudFailure) {
        return rd.Failure(lastError);
      }
      return rd.Failure(
        NextcloudFailure(
          message: _getNextcloudErrorMessage(lastError),
          originalError: lastError,
        ),
      );
    } on Object catch (e) {
      stopwatch.stop();
      if (e is NextcloudFailure) {
        return rd.Failure(e);
      }
      return rd.Failure(
        NextcloudFailure(
          message: _getNextcloudErrorMessage(e),
          originalError: e,
        ),
      );
    }
  }

  @override
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
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao testar conexão Nextcloud',
        e,
        stackTrace,
      );
      return rd.Failure(
        NextcloudFailure(
          message:
              'Erro ao testar conexão Nextcloud: ${_getNextcloudErrorMessage(e)}',
          originalError: e,
        ),
      );
    }
  }

  @override
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

            final hasProtectedFile = await _folderHasProtectedFile(
              dio: dio,
              config: config,
              folderPath: folderPath,
              protectedShortIds: config.protectedBackupIdShortPrefixes,
            );
            if (hasProtectedFile) {
              LoggerService.debug(
                'Pasta Nextcloud protegida (retenção Sybase): $folderName',
              );
              continue;
            }

            final deleteUrl = NextcloudWebdavUtils.buildDavUrl(
              serverUrl: config.serverUrl,
              username: config.username,
              path: folderPath,
            );

            await dio.deleteUri(deleteUrl);
            deletedCount++;
          }
        } on Object catch (e) {
          LoggerService.debug(
            'Nextcloud: nome de pasta não é data válida, ignorando: $folderName — $e',
          );
        }
      }

      return rd.Success(deletedCount);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao limpar backups Nextcloud',
        e,
        stackTrace,
      );
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

  Future<bool> _folderHasProtectedFile({
    required Dio dio,
    required NextcloudDestinationConfig config,
    required String folderPath,
    required Set<String> protectedShortIds,
  }) async {
    if (protectedShortIds.isEmpty) return false;

    try {
      final url = NextcloudWebdavUtils.buildDavUrl(
        serverUrl: config.serverUrl,
        username: config.username,
        path: folderPath,
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
      if (xmlStr.isEmpty) return false;

      final names = NextcloudWebdavUtils.parseDirectChildNamesFromPropfind(
        xmlStr: xmlStr,
        requestedPath: url.path,
      );

      for (final name in names) {
        if (SybaseBackupPathSuffix.isPathProtected(name, protectedShortIds)) {
          return true;
        }
      }
    } on Object catch (e) {
      LoggerService.debug(
        'Nextcloud: erro ao listar pasta $folderPath — $e',
      );
    }
    return false;
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

  Future<rd.Result<void>> _validateUploadedFileIntegrity({
    required Dio dio,
    required Uri uploadUrl,
    required int fileSize,
    required String localSha256,
  }) async {
    final headSizeResult = await _validateRemoteContentLength(
      dio: dio,
      uploadUrl: uploadUrl,
      expectedSize: fileSize,
    );
    if (headSizeResult.isError()) {
      return rd.Failure(headSizeResult.exceptionOrNull()!);
    }

    for (var attempt = 0; attempt < _integrityReadBackAttempts; attempt++) {
      try {
        final response = await dio.getUri(
          uploadUrl,
          options: Options(responseType: ResponseType.stream),
        );
        final body = response.data;
        if (body is! ResponseBody) {
          throw Exception('Resposta inválida no read-back Nextcloud');
        }
        final remoteSha256 = await FileHashUtils.computeSha256FromStream(
          body.stream,
        );
        if (remoteSha256.toLowerCase() == localSha256.toLowerCase()) {
          return const rd.Success(());
        }
        return rd.Failure(
          NextcloudFailure(
            message:
                'Falha de integridade no Nextcloud: hash remoto difere '
                'do arquivo local (SHA-256).',
            code: FailureCodes.integrityValidationFailed,
            originalError: Exception(
              'Nextcloud SHA-256 mismatch: '
              'local=$localSha256 remote=$remoteSha256',
            ),
          ),
        );
      } on Object catch (e) {
        if (attempt < _integrityReadBackAttempts - 1) {
          await Future.delayed(_integrityReadBackDelay);
          continue;
        }
        return rd.Failure(
          NextcloudFailure(
            message:
                'Não foi possível confirmar integridade no Nextcloud por '
                'read-back (download de validação).',
            code: FailureCodes.integrityValidationInconclusive,
            originalError: e,
          ),
        );
      }
    }

    return const rd.Failure(
      NextcloudFailure(
        message: 'Não foi possível confirmar integridade no Nextcloud.',
        code: FailureCodes.integrityValidationInconclusive,
      ),
    );
  }

  Future<rd.Result<void>> _validateRemoteContentLength({
    required Dio dio,
    required Uri uploadUrl,
    required int expectedSize,
  }) async {
    try {
      final headResponse = await dio.headUri(uploadUrl);
      final contentLengthStr = headResponse.headers.value('content-length');
      if (contentLengthStr == null || contentLengthStr.isEmpty) {
        return const rd.Failure(
          NextcloudFailure(
            message:
                'Não foi possível validar integridade no Nextcloud '
                '(content-length ausente no HEAD).',
            code: FailureCodes.integrityValidationInconclusive,
          ),
        );
      }
      final remoteSize = int.tryParse(contentLengthStr);
      if (remoteSize == null) {
        return const rd.Failure(
          NextcloudFailure(
            message:
                'Não foi possível validar integridade no Nextcloud '
                '(content-length inválido no HEAD).',
            code: FailureCodes.integrityValidationInconclusive,
          ),
        );
      }
      if (remoteSize != expectedSize) {
        return rd.Failure(
          NextcloudFailure(
            message:
                'Falha de integridade no Nextcloud: tamanho remoto '
                'diverge do arquivo local. Local: $expectedSize, '
                'Remoto: $remoteSize',
            code: FailureCodes.integrityValidationFailed,
            originalError: Exception(
              'Nextcloud content-length mismatch: '
              'local=$expectedSize remote=$remoteSize',
            ),
          ),
        );
      }
      return const rd.Success(());
    } on Object catch (e) {
      return rd.Failure(
        NextcloudFailure(
          message:
              'Não foi possível validar integridade no Nextcloud '
              '(falha na consulta HEAD).',
          code: FailureCodes.integrityValidationInconclusive,
          originalError: e,
        ),
      );
    }
  }

  String _getNextcloudErrorMessage(dynamic e) {
    if (e is Failure && e.code != null) {
      if (e.code == FailureCodes.integrityValidationInconclusive) {
        return 'Não foi possível confirmar a integridade no Nextcloud.\n'
            'Detalhes: ${e.message}';
      }
      if (e.code == FailureCodes.integrityValidationFailed) {
        return 'Falha de integridade no Nextcloud: arquivo remoto não confere '
            'com o original.\n'
            'Detalhes: ${e.message}';
      }
    }

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
