import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  group('AutoUpdateService.tryAcquireGlobalLock', () {
    test('acquires once and rejects a second concurrent holder', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_lock_test');
      final locksDir = Directory(p.join(tempDir.path, 'locks'));

      final first = await AutoUpdateService.tryAcquireGlobalLock(
        locksDir: locksDir,
        metadata: {
          'source': AppUpdateSource.manual.name,
          'attempt': '1',
          'currentVersion': '3.0.1',
          'stage': 'fetching_feed',
        },
      );
      final second = await AutoUpdateService.tryAcquireGlobalLock(
        locksDir: locksDir,
        metadata: {
          'source': AppUpdateSource.periodic.name,
          'attempt': '2',
          'currentVersion': '3.0.1',
          'stage': 'fetching_feed',
        },
      );

      expect(first, isNotNull);
      expect(second, isNull);
      expect(
        await File(p.join(locksDir.path, 'auto_update.lock')).readAsString(),
        allOf(contains('source=manual'), contains('attempt=1')),
      );

      await first?.release();
      await tempDir.delete(recursive: true);
    });

    test('replaces a stale lock file', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_lock_test');
      final locksDir = Directory(p.join(tempDir.path, 'locks'));
      await locksDir.create(recursive: true);
      final lockFile = File(p.join(locksDir.path, 'auto_update.lock'));
      await lockFile.writeAsString('stale');
      await lockFile.setLastModified(
        DateTime.now().subtract(const Duration(hours: 4)),
      );

      final handle = await AutoUpdateService.tryAcquireGlobalLock(
        locksDir: locksDir,
        metadata: {
          'source': AppUpdateSource.manual.name,
          'attempt': '3',
          'currentVersion': '3.0.1',
          'stage': 'fetching_feed',
        },
      );

      expect(handle, isNotNull);
      expect(
        await lockFile.readAsString(),
        allOf(contains('acquiredAt='), contains('source=manual')),
      );

      await handle?.release();
      await tempDir.delete(recursive: true);
    });
  });

  group('AutoUpdateService runtime pipeline', () {
    test(
      'downloads validates and launches installer silently from appcast',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_runtime_test',
        );
        final locksDir = Directory(p.join(tempDir.path, 'locks'));
        final updatesDir = Directory(p.join(tempDir.path, 'updates'));
        final installerBytes = <int>[1, 2, 3, 4, 5, 6];
        final payloadFile = File(p.join(tempDir.path, 'payload.exe'));
        await payloadFile.writeAsBytes(installerBytes);
        final installerSha256 = await FileHashUtils.computeSha256(payloadFile);

        late final HttpServer server;
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final baseUrl = 'http://${server.address.address}:${server.port}';

        unawaited(
          server.forEach((request) async {
            if (request.uri.path == '/appcast.xml') {
              request.response.headers.contentType = ContentType(
                'application',
                'xml',
                charset: 'utf-8',
              );
              request.response.write(
                _buildFeed(
                  items: [
                    _buildItem(
                      version: '3.0.2',
                      length: installerBytes.length,
                      sha256: installerSha256,
                      url: '$baseUrl/BackupDatabase-Setup-3.0.2.exe',
                    ),
                  ],
                ),
              );
            } else if (request.uri.path == '/BackupDatabase-Setup-3.0.2.exe') {
              request.response.add(installerBytes);
            } else {
              request.response.statusCode = HttpStatus.notFound;
            }
            await request.response.close();
          }),
        );

        final snapshots = <AppUpdateSnapshot>[];
        String? launchedExecutable;
        List<String>? launchedArguments;
        int? exitCode;
        String? lockMetadataAtInstall;
        var beforeInstallCalls = 0;

        final service = AutoUpdateService(
          dio: Dio(),
          packageInfoLoader: () async => PackageInfo(
            appName: 'Backup Database',
            packageName: 'backup_database',
            version: '3.0.1',
            buildNumber: '',
          ),
          feedUrlReader: () => '$baseUrl/appcast.xml',
          locksDirectoryResolver: () async => locksDir,
          updatesDirectoryResolver: () async => updatesDir,
          detachedProcessStarter: (executable, arguments) async {
            launchedExecutable = executable;
            launchedArguments = arguments;
          },
          exitProcess: (code) {
            exitCode = code;
          },
        );
        final subscription = service.snapshots.listen(snapshots.add);
        service.beforeInstallHook = () async {
          beforeInstallCalls++;
          lockMetadataAtInstall = await File(
            p.join(locksDir.path, 'auto_update.lock'),
          ).readAsString();
        };

        await service.initialize();
        await service.checkNow(source: AppUpdateSource.manual);

        expect(beforeInstallCalls, 1);
        expect(exitCode, 0);
        expect(launchedExecutable, isNotNull);
        expect(
          p.basename(launchedExecutable!),
          'BackupDatabase-Setup-3.0.2.exe',
        );
        expect(
          launchedArguments,
          const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
        );
        expect(
          snapshots.map((snapshot) => snapshot.status),
          containsAll(<AppUpdateStatus>[
            AppUpdateStatus.checking,
            AppUpdateStatus.updateAvailable,
            AppUpdateStatus.downloading,
            AppUpdateStatus.installing,
          ]),
        );
        expect(snapshots.last.lastAttemptNumber, 1);
        expect(snapshots.last.lastDownloadDuration, isNotNull);
        expect(snapshots.last.lastCheckDuration, isNotNull);
        expect(snapshots.last.lastFailureStage, isNull);
        expect(snapshots.last.stage, AppUpdateStage.completed);
        expect(
          lockMetadataAtInstall,
          allOf(
            contains('targetVersion=3.0.2'),
            contains('stage=preparing_install'),
          ),
        );

        final downloadedInstaller = File(launchedExecutable!);
        expect(await downloadedInstaller.exists(), isTrue);
        expect(
          await FileHashUtils.computeSha256(downloadedInstaller),
          installerSha256,
        );

        await subscription.cancel();
        await service.dispose();
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      },
      skip: !Platform.isWindows,
    );
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
  String? url,
  String pubDate = 'Sun, 19 Apr 2026 17:07:49 +0000',
}) {
  final shaAttr = sha256 == null ? '' : ' sha256="$sha256"';
  return '''
<item>
  <title>Version $version</title>
  <pubDate>$pubDate</pubDate>
  <description>Automatic update via GitHub Release.</description>
  <enclosure
    url="${url ?? 'https://example.com/BackupDatabase-Setup-$version.exe'}"
    sparkle:version="$version"
    sparkle:os="windows"
    length="$length"
    type="application/octet-stream"$shaAttr />
</item>
''';
}
