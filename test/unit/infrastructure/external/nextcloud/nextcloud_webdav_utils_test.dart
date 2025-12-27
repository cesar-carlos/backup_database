import 'package:flutter_test/flutter_test.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_webdav_utils.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';

void main() {
  group('NextcloudWebdavUtils', () {
    test('buildDavUrl deve montar URL WebDAV com encoding correto', () {
      final url = NextcloudWebdavUtils.buildDavUrl(
        serverUrl: 'https://cloud.example.com',
        username: 'john',
        path: '/Backups/2025-12-27/a b.zip',
      );

      expect(
        url.toString(),
        'https://cloud.example.com/remote.php/dav/files/john/Backups/2025-12-27/a%20b.zip',
      );
    });

    test('parseCollectionNamesFromPropfind deve retornar apenas pastas filhas', () {
      const xmlStr = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/remote.php/dav/files/john/Backups/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/dav/files/john/Backups/2025-12-01/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/dav/files/john/Backups/file.zip</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''';

      final folders = NextcloudWebdavUtils.parseCollectionNamesFromPropfind(
        xmlStr: xmlStr,
        requestedPath: '/remote.php/dav/files/john/Backups/',
      );

      expect(folders, ['2025-12-01']);
    });
  });

  group('NextcloudDestinationConfig', () {
    test('toJson/fromJson deve manter valores (incluindo segredo criptografado)', () {
      final encrypted = EncryptionService.encrypt('secret');

      final config = NextcloudDestinationConfig(
        serverUrl: 'https://cloud.example.com',
        username: 'john',
        appPassword: encrypted,
        authMode: NextcloudAuthMode.userPassword,
        remotePath: '/Backups',
        folderName: 'Backups',
        allowInvalidCertificates: true,
        retentionDays: 7,
      );

      final restored = NextcloudDestinationConfig.fromJson(config.toJson());
      expect(restored.serverUrl, config.serverUrl);
      expect(restored.username, config.username);
      expect(restored.appPassword, config.appPassword);
      expect(restored.authMode, config.authMode);
      expect(restored.remotePath, config.remotePath);
      expect(restored.folderName, config.folderName);
      expect(restored.allowInvalidCertificates, config.allowInvalidCertificates);
      expect(restored.retentionDays, config.retentionDays);
    });
  });
}


