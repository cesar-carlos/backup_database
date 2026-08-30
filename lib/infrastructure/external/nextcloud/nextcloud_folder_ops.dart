import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_webdav_utils.dart';
import 'package:dio/dio.dart';

const _propfindResourcetypeBody = '''
<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype />
  </d:prop>
</d:propfind>
''';

class NextcloudFolderOps {
  const NextcloudFolderOps();

  Future<void> ensureFolderExists({
    required Dio dio,
    required NextcloudDestinationConfig config,
    required String path,
  }) async {
    final url = NextcloudWebdavUtils.buildDavUrl(
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

  Future<List<String>> listCollections({
    required Dio dio,
    required NextcloudDestinationConfig config,
    required String path,
  }) async {
    final url = NextcloudWebdavUtils.buildDavUrl(
      serverUrl: config.serverUrl,
      username: config.username,
      path: path,
    );

    final response = await dio.requestUri(
      url,
      data: _propfindResourcetypeBody,
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

  Future<List<String>> listDirectChildNames({
    required Dio dio,
    required NextcloudDestinationConfig config,
    required String folderPath,
  }) async {
    final url = NextcloudWebdavUtils.buildDavUrl(
      serverUrl: config.serverUrl,
      username: config.username,
      path: folderPath,
    );

    final response = await dio.requestUri(
      url,
      data: _propfindResourcetypeBody,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1', 'Content-Type': 'application/xml'},
      ),
    );

    final data = response.data;
    final xmlStr = data is String ? data : data?.toString() ?? '';
    if (xmlStr.isEmpty) return const [];

    return NextcloudWebdavUtils.parseDirectChildNamesFromPropfind(
      xmlStr: xmlStr,
      requestedPath: url.path,
    );
  }
}
