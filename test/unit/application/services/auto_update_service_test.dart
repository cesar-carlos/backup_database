import 'dart:io';

import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

const _sparkleNs = 'http://www.andymatuschak.org/xml-namespaces/sparkle';

void main() {
  group('AutoUpdateService.parseAppcast', () {
    test('parses a valid Windows release with sha256 and length', () {
      final releases = AutoUpdateService.parseAppcast(
        _buildFeed(
          items: [
            _buildItem(
              version: '3.0.1',
              length: 12345,
              sha256: 'abc123',
            ),
          ],
        ),
      );

      expect(releases, hasLength(1));
      expect(releases.single.version, Version.parse('3.0.1'));
      expect(releases.single.fileSizeBytes, 12345);
      expect(releases.single.sha256, 'abc123');
    });

    test('deduplicates by version keeping the newest pubDate', () {
      final releases = AutoUpdateService.parseAppcast(
        _buildFeed(
          items: [
            _buildItem(
              version: '3.0.1',
              pubDate: 'Sun, 19 Apr 2026 17:07:49 +0000',
              length: 111,
              sha256: 'old',
            ),
            _buildItem(
              version: '3.0.1',
              pubDate: 'Mon, 20 Apr 2026 17:07:49 +0000',
              length: 222,
              sha256: 'new',
            ),
          ],
        ),
      );

      expect(releases, hasLength(1));
      expect(releases.single.fileSizeBytes, 222);
      expect(releases.single.sha256, 'new');
    });

    test('ignores releases without sha256', () {
      final releases = AutoUpdateService.parseAppcast(
        _buildFeed(
          items: [
            _buildItem(
              version: '3.0.1',
              length: 12345,
              sha256: null,
            ),
          ],
        ),
      );

      expect(releases, isEmpty);
    });
  });

  group('AutoUpdateService.evaluateRelease', () {
    test('returns upToDate when no release is newer', () {
      final decision = AutoUpdateService.evaluateRelease(
        releases: [
          _release(version: '3.0.1'),
          _release(version: '3.0.0'),
        ],
        currentVersion: Version.parse('3.0.1'),
      );

      expect(decision.isUpdateAvailable, isFalse);
      expect(decision.latestRelease, isNull);
    });

    test('returns the newest release greater than current version', () {
      final decision = AutoUpdateService.evaluateRelease(
        releases: [
          _release(version: '3.0.2'),
          _release(version: '3.0.1'),
        ],
        currentVersion: Version.parse('3.0.1'),
      );

      expect(decision.isUpdateAvailable, isTrue);
      expect(decision.latestRelease?.targetVersion, '3.0.2');
    });
  });

  group('AutoUpdateService.validateDownloadedInstaller', () {
    test('accepts installer when size and hash match', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_update_test');
      final installer = File(p.join(tempDir.path, 'installer.exe'));
      await installer.writeAsBytes([1, 2, 3, 4]);
      final sha256 = await FileHashUtils.computeSha256(installer);

      final release = AppcastRelease(
        version: Version.parse('3.0.2'),
        downloadUrl: 'https://example.com/BackupDatabase-Setup-3.0.2.exe',
        fileSizeBytes: await installer.length(),
        sha256: sha256,
        publishedAt: DateTime.utc(2026, 4, 19),
        title: 'Version 3.0.2',
        description: 'Automatic update via GitHub Release.',
      );

      await AutoUpdateService.validateDownloadedInstaller(installer, release);

      await tempDir.delete(recursive: true);
    });

    test('throws when installer size mismatches', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_update_test');
      final installer = File(p.join(tempDir.path, 'installer.exe'));
      await installer.writeAsBytes([1, 2, 3, 4]);
      final sha256 = await FileHashUtils.computeSha256(installer);

      final release = AppcastRelease(
        version: Version.parse('3.0.2'),
        downloadUrl: 'https://example.com/BackupDatabase-Setup-3.0.2.exe',
        fileSizeBytes: 999,
        sha256: sha256,
        publishedAt: DateTime.utc(2026, 4, 19),
        title: 'Version 3.0.2',
        description: 'Automatic update via GitHub Release.',
      );

      await expectLater(
        AutoUpdateService.validateDownloadedInstaller(installer, release),
        throwsStateError,
      );

      await tempDir.delete(recursive: true);
    });
  });
}

AppcastRelease _release({required String version}) {
  return AppcastRelease(
    version: Version.parse(version),
    downloadUrl: 'https://example.com/BackupDatabase-Setup-$version.exe',
    fileSizeBytes: 100,
    sha256: 'abc123',
    publishedAt: DateTime.utc(2026, 4, 19),
    title: 'Version $version',
    description: 'Automatic update via GitHub Release.',
  );
}

String _buildFeed({required List<String> items}) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="$_sparkleNs">
  <channel>
    <title>Backup Database Updates</title>
    <link>https://github.com/cesar-carlos/backup_database/releases</link>
    <description>Backup Database updates feed</description>
    ${items.join('\n')}
  </channel>
</rss>
''';
}

String _buildItem({
  required String version,
  required int length,
  required String? sha256,
  String pubDate = 'Sun, 19 Apr 2026 17:07:49 +0000',
}) {
  final shaAttr = sha256 == null ? '' : ' sha256="$sha256"';
  return '''
<item>
  <title>Version $version</title>
  <pubDate>$pubDate</pubDate>
  <description>Automatic update via GitHub Release.</description>
  <enclosure
    url="https://example.com/BackupDatabase-Setup-$version.exe"
    sparkle:version="$version"
    sparkle:os="windows"
    length="$length"
    type="application/octet-stream"$shaAttr />
</item>
''';
}
