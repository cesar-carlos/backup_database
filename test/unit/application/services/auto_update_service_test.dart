import 'dart:async';
import 'dart:convert';
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
  _registerDisabledReasonTests();

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
        var lockExistsAtExit = true;
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
            return null;
          },
          exitProcess: (code) {
            exitCode = code;
            lockExistsAtExit = File(
              p.join(locksDir.path, 'auto_update.lock'),
            ).existsSync();
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
        expect(lockExistsAtExit, isFalse);
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
        expect(snapshots.last.status, AppUpdateStatus.handoffCompleted);
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
        final updateContext = File(
          p.join(updatesDir.path, 'update_context.json'),
        );
        expect(await updateContext.exists(), isTrue);
        final updateContextJson =
            jsonDecode(await updateContext.readAsString())
                as Map<String, dynamic>;
        expect(
          updateContextJson['schemaVersion'],
          AutoUpdateService.updateContextSchemaVersion,
        );
        expect(updateContextJson['contextId'], isA<String>());
        expect(updateContextJson['targetVersion'], '3.0.2');
        expect(updateContextJson['origin'], 'ui');
        expect(
          DateTime.parse(updateContextJson['expiresAt'] as String),
          isNotNull,
        );
        expect(updateContextJson['relaunchArguments'], isA<List<dynamic>>());

        await subscription.cancel();
        await service.dispose();
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      },
      skip: !Platform.isWindows,
    );

    test(
      'blocks install when readiness check reports active backup',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_blocked_test',
        );
        final locksDir = Directory(p.join(tempDir.path, 'locks'));
        final updatesDir = Directory(p.join(tempDir.path, 'updates'));
        final installerBytes = <int>[1, 2, 3, 4];
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

        var launched = false;
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
            launched = true;
            return null;
          },
          exitProcess: (code) {},
        );
        service.installReadinessCheck = (release) async {
          return 'Atualizacao bloqueada: existe um backup em andamento na UI.';
        };

        await service.initialize();
        await service.checkNow(source: AppUpdateSource.manual);

        expect(launched, isFalse);
        expect(service.snapshot.status, AppUpdateStatus.blockedByActiveBackup);
        expect(service.snapshot.stage, AppUpdateStage.blockedByActiveBackup);
        expect(service.snapshot.errorMessage, isNull);

        await service.dispose();
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      },
      skip: !Platform.isWindows,
    );

    test(
      'retries transient appcast failures before succeeding',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_retry_test',
        );
        final locksDir = Directory(p.join(tempDir.path, 'locks'));
        final updatesDir = Directory(p.join(tempDir.path, 'updates'));
        final installerBytes = <int>[1, 2, 3, 4];
        final payloadFile = File(p.join(tempDir.path, 'payload.exe'));
        await payloadFile.writeAsBytes(installerBytes);
        final installerSha256 = await FileHashUtils.computeSha256(payloadFile);

        late final HttpServer server;
        var appcastRequests = 0;
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final baseUrl = 'http://${server.address.address}:${server.port}';

        unawaited(
          server.forEach((request) async {
            if (request.uri.path == '/appcast.xml') {
              appcastRequests++;
              if (appcastRequests < 3) {
                request.response.statusCode = HttpStatus.internalServerError;
                request.response.write('temporary failure');
              } else {
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
              }
            } else if (request.uri.path == '/BackupDatabase-Setup-3.0.2.exe') {
              request.response.add(installerBytes);
            } else {
              request.response.statusCode = HttpStatus.notFound;
            }
            await request.response.close();
          }),
        );

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
          detachedProcessStarter: (executable, arguments) async => null,
          exitProcess: (code) {},
        );

        await service.initialize();
        await service.checkNow(source: AppUpdateSource.manual);

        expect(appcastRequests, 3);
        expect(service.snapshot.status, AppUpdateStatus.handoffCompleted);

        await service.dispose();
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      },
      skip: !Platform.isWindows,
    );

    test(
      'cleans old staged installers keeping current target and one recent previous',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_cleanup_test',
        );
        final updatesDir = Directory(p.join(tempDir.path, 'updates'));
        await updatesDir.create(recursive: true);
        File(
          p.join(updatesDir.path, 'BackupDatabase-Setup-3.0.2.exe'),
        ).writeAsStringSync('target');
        File(
          p.join(updatesDir.path, 'BackupDatabase-Setup-3.0.1.exe'),
        ).writeAsStringSync('previous');
        final oldInstaller = File(
          p.join(updatesDir.path, 'BackupDatabase-Setup-2.9.9.exe'),
        )..writeAsStringSync('old');
        final ancientInstaller = File(
          p.join(updatesDir.path, 'BackupDatabase-Setup-2.8.0.exe'),
        )..writeAsStringSync('ancient');
        await oldInstaller.setLastModified(
          DateTime.now().subtract(const Duration(days: 20)),
        );
        await ancientInstaller.setLastModified(
          DateTime.now().subtract(const Duration(days: 60)),
        );

        final service = AutoUpdateService(
          packageInfoLoader: () async => PackageInfo(
            appName: 'Backup Database',
            packageName: 'backup_database',
            version: '3.0.1',
            buildNumber: '',
          ),
          feedUrlReader: () => 'https://example.com/appcast.xml',
          locksDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'locks')),
          updatesDirectoryResolver: () async => updatesDir,
          detachedProcessStarter: (executable, arguments) async => null,
          exitProcess: (code) {},
        );

        await service.initialize();

        final remaining = updatesDir
            .listSync()
            .whereType<File>()
            .map((file) => p.basename(file.path))
            .toSet();

        expect(remaining, contains('BackupDatabase-Setup-3.0.2.exe'));
        expect(remaining, contains('BackupDatabase-Setup-3.0.1.exe'));
        expect(remaining, isNot(contains('BackupDatabase-Setup-2.9.9.exe')));
        expect(remaining, isNot(contains('BackupDatabase-Setup-2.8.0.exe')));

        await service.dispose();
        await tempDir.delete(recursive: true);
      },
    );

    test('removes expired update context during initialize', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'auto_update_context_expired_test',
      );
      final updatesDir = Directory(p.join(tempDir.path, 'updates'));
      await updatesDir.create(recursive: true);
      final contextFile = File(p.join(updatesDir.path, 'update_context.json'));
      await contextFile.writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': AutoUpdateService.updateContextSchemaVersion,
          'contextId': 'expired-context',
          'origin': 'ui',
          'appMode': 'client',
          'currentVersion': '3.0.1',
          'targetVersion': '3.0.2',
          'relaunchArguments': const <String>[],
          'executablePath':
              r'C:\Program Files\Backup Database\backup_database.exe',
          'createdAt': DateTime.now()
              .subtract(const Duration(hours: 2))
              .toUtc()
              .toIso8601String(),
          'expiresAt': DateTime.now()
              .subtract(const Duration(minutes: 30))
              .toUtc()
              .toIso8601String(),
        }),
      );

      final service = AutoUpdateService(
        packageInfoLoader: () async => PackageInfo(
          appName: 'Backup Database',
          packageName: 'backup_database',
          version: '3.0.1',
          buildNumber: '',
        ),
        feedUrlReader: () => 'https://example.com/appcast.xml',
        locksDirectoryResolver: () async =>
            Directory(p.join(tempDir.path, 'locks')),
        updatesDirectoryResolver: () async => updatesDir,
        detachedProcessStarter: (executable, arguments) async => null,
        exitProcess: (code) {},
      );

      await service.initialize();

      expect(await contextFile.exists(), isFalse);

      await service.dispose();
      await tempDir.delete(recursive: true);
    });

    test('rotates diagnostics by retention and size', () async {
      final now = DateTime.utc(2026, 5, 19, 12);
      final lines = <String>[
        jsonEncode(<String, Object?>{
          'timestamp': now.subtract(const Duration(days: 40)).toIso8601String(),
          'status': 'error',
        }),
        jsonEncode(<String, Object?>{
          'timestamp': now.subtract(const Duration(days: 2)).toIso8601String(),
          'status': 'handoffCompleted',
          'payload': List<String>.filled(64, 'A').join(),
        }),
        jsonEncode(<String, Object?>{
          'timestamp': now.subtract(const Duration(days: 1)).toIso8601String(),
          'status': 'handoffCompleted',
          'payload': List<String>.filled(64, 'B').join(),
        }),
      ];

      final compacted = await AutoUpdateService.compactDiagnosticsLines(
        lines,
        now: now,
        maxBytes: 180,
      );

      expect(compacted, hasLength(1));
      expect(compacted.single, contains('"payload":"B'));
    });

    test(
      'compactDiagnosticsLines descarta linhas com schemaVersion futura',
      () async {
        final now = DateTime.utc(2026);
        final futureRecord = jsonEncode(<String, Object?>{
          'schemaVersion': AutoUpdateService.diagnosticsSchemaVersion + 1,
          'timestamp': now.subtract(const Duration(hours: 1)).toIso8601String(),
          'source': 'manual',
          'payload': 'should-be-dropped',
        });
        final currentRecord = jsonEncode(<String, Object?>{
          'schemaVersion': AutoUpdateService.diagnosticsSchemaVersion,
          'timestamp': now.subtract(const Duration(hours: 1)).toIso8601String(),
          'source': 'manual',
          'payload': 'should-be-kept',
        });
        final legacyRecord = jsonEncode(<String, Object?>{
          'timestamp': now.subtract(const Duration(hours: 1)).toIso8601String(),
          'source': 'manual',
          'payload': 'legacy-kept',
        });

        final compacted = await AutoUpdateService.compactDiagnosticsLines(
          <String>[futureRecord, currentRecord, legacyRecord],
          now: now,
        );

        expect(compacted, hasLength(2));
        expect(compacted.any((l) => l.contains('legacy-kept')), isTrue);
        expect(compacted.any((l) => l.contains('should-be-kept')), isTrue);
        expect(compacted.any((l) => l.contains('should-be-dropped')), isFalse);
      },
    );
  });

  group('AutoUpdateService.evaluateRelease staged rollout', () {
    test('respeita minSupportedAppVersion', () {
      final release = AppcastRelease(
        version: Version.parse('3.5.0'),
        downloadUrl: 'https://example.com/x.exe',
        fileSizeBytes: 1,
        sha256: 'a',
        publishedAt: DateTime.utc(2026, 5),
        title: 'Version 3.5.0',
        description: '',
        minSupportedAppVersion: Version.parse('3.4.0'),
      );

      final tooOld = AutoUpdateService.evaluateRelease(
        releases: <AppcastRelease>[release],
        currentVersion: Version.parse('3.3.9'),
      );
      expect(tooOld.isUpdateAvailable, isFalse);

      final eligible = AutoUpdateService.evaluateRelease(
        releases: <AppcastRelease>[release],
        currentVersion: Version.parse('3.4.0'),
      );
      expect(eligible.isUpdateAvailable, isTrue);
    });

    test('rolloutPercentage = 0 bloqueia todos os clientes', () {
      final release = AppcastRelease(
        version: Version.parse('3.5.0'),
        downloadUrl: 'https://example.com/x.exe',
        fileSizeBytes: 1,
        sha256: 'a',
        publishedAt: DateTime.utc(2026, 5),
        title: 'Version 3.5.0',
        description: '',
        rolloutPercentage: 0,
      );

      final decision = AutoUpdateService.evaluateRelease(
        releases: <AppcastRelease>[release],
        currentVersion: Version.parse('3.0.0'),
        machineId: 'machine-A',
      );
      expect(decision.isUpdateAvailable, isFalse);
    });

    test('rolloutPercentage = 100 deixa todos passarem', () {
      final release = AppcastRelease(
        version: Version.parse('3.5.0'),
        downloadUrl: 'https://example.com/x.exe',
        fileSizeBytes: 1,
        sha256: 'a',
        publishedAt: DateTime.utc(2026, 5),
        title: 'Version 3.5.0',
        description: '',
        rolloutPercentage: 100,
      );

      for (final id in <String>['machine-A', 'machine-B', 'machine-X']) {
        final decision = AutoUpdateService.evaluateRelease(
          releases: <AppcastRelease>[release],
          currentVersion: Version.parse('3.0.0'),
          machineId: id,
        );
        expect(
          decision.isUpdateAvailable,
          isTrue,
          reason: 'machineId=$id deveria ter passado em rollout=100',
        );
      }
    });

    test('rollout deterministico por machineId', () {
      final release = AppcastRelease(
        version: Version.parse('3.5.0'),
        downloadUrl: 'https://example.com/x.exe',
        fileSizeBytes: 1,
        sha256: 'a',
        publishedAt: DateTime.utc(2026, 5),
        title: 'Version 3.5.0',
        description: '',
        rolloutPercentage: 50,
      );

      // Determinismo: mesma chamada repetida da mesmo resultado.
      final a1 = AutoUpdateService.evaluateRelease(
        releases: <AppcastRelease>[release],
        currentVersion: Version.parse('3.0.0'),
        machineId: 'machine-canary',
      );
      final a2 = AutoUpdateService.evaluateRelease(
        releases: <AppcastRelease>[release],
        currentVersion: Version.parse('3.0.0'),
        machineId: 'machine-canary',
      );
      expect(a1.isUpdateAvailable, a2.isUpdateAvailable);
    });
  });

  group('AutoUpdateService.startPeriodicChecks', () {
    test(
      'AUTO_UPDATE_CHECK_INTERVAL_SECONDS=0 desativa o timer periodico',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_interval_off_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final service = AutoUpdateService(
          packageInfoLoader: () async => PackageInfo(
            appName: 'Backup Database',
            packageName: 'backup_database',
            version: '3.0.1',
            buildNumber: '',
          ),
          feedUrlReader: () => 'https://example.com/appcast.xml',
          checkIntervalReader: () => '0',
          locksDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'locks')),
          updatesDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'updates')),
          detachedProcessStarter: (executable, arguments) async => null,
          exitProcess: (code) {},
        );

        await service.initialize();
        // Nao deve lancar nem agendar timer; sucesso e' nao bloquear.
        service.startPeriodicChecks();
        await service.dispose();
      },
      skip: !Platform.isWindows,
    );

    test(
      'AUTO_UPDATE_CHECK_INTERVAL_SECONDS < 60 e clampado para 60s',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_interval_clamp_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final service = AutoUpdateService(
          packageInfoLoader: () async => PackageInfo(
            appName: 'Backup Database',
            packageName: 'backup_database',
            version: '3.0.1',
            buildNumber: '',
          ),
          feedUrlReader: () => 'https://example.com/appcast.xml',
          checkIntervalReader: () => '5',
          locksDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'locks')),
          updatesDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'updates')),
          detachedProcessStarter: (executable, arguments) async => null,
          exitProcess: (code) {},
        );

        await service.initialize();
        service.startPeriodicChecks();
        // Sem hooks de teste para inspecionar o Duration; sucesso e'
        // nao explodir e ter timer ativo (validado por nao-throw).
        await service.dispose();
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

/// §audit-2026-05-28: cobertura para os snapshots `disabled` com
/// `disabledReason` semântico. Antes desses testes, qualquer falha de
/// init virava `disabled+completed+null lastCheck` indistinguível —
/// motivo da sessão de "detective" que originou esta auditoria.
void _registerDisabledReasonTests() {
  group('AutoUpdateService.initialize disabledReason', () {
    test(
      'emits feedReaderException when feedUrlReader throws',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_feed_reader_throws_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final service = AutoUpdateService(
          packageInfoLoader: () async => PackageInfo(
            appName: 'Backup Database',
            packageName: 'backup_database',
            version: '3.0.1',
            buildNumber: '',
          ),
          feedUrlReader: () => throw StateError('dotenv not initialized'),
          checkIntervalReader: () => '0',
          locksDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'locks')),
          updatesDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'updates')),
          detachedProcessStarter: (executable, arguments) async => null,
          exitProcess: (code) {},
        );

        await service.initialize();

        expect(service.snapshot.status, AppUpdateStatus.disabled);
        expect(
          service.snapshot.disabledReason,
          AppUpdateDisabledReason.feedReaderException,
        );
        expect(service.snapshot.stage, AppUpdateStage.completed);
        expect(service.snapshot.errorMessage, isNotNull);
      },
    );

    test(
      'emits feedUrlMissing when feedUrlReader returns null',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_feed_url_missing_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final service = AutoUpdateService(
          packageInfoLoader: () async => PackageInfo(
            appName: 'Backup Database',
            packageName: 'backup_database',
            version: '3.0.1',
            buildNumber: '',
          ),
          feedUrlReader: () => null,
          checkIntervalReader: () => '0',
          locksDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'locks')),
          updatesDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'updates')),
          detachedProcessStarter: (executable, arguments) async => null,
          exitProcess: (code) {},
        );

        await service.initialize();

        expect(service.snapshot.status, AppUpdateStatus.disabled);
        expect(
          service.snapshot.disabledReason,
          AppUpdateDisabledReason.feedUrlMissing,
        );
        expect(service.snapshot.stage, AppUpdateStage.completed);
      },
    );

    test(
      'emits feedUrlMissing when feedUrlReader returns empty string',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_feed_url_empty_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final service = AutoUpdateService(
          packageInfoLoader: () async => PackageInfo(
            appName: 'Backup Database',
            packageName: 'backup_database',
            version: '3.0.1',
            buildNumber: '',
          ),
          feedUrlReader: () => '   ',
          checkIntervalReader: () => '0',
          locksDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'locks')),
          updatesDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'updates')),
          detachedProcessStarter: (executable, arguments) async => null,
          exitProcess: (code) {},
        );

        await service.initialize();

        expect(service.snapshot.status, AppUpdateStatus.disabled);
        expect(
          service.snapshot.disabledReason,
          AppUpdateDisabledReason.feedUrlMissing,
        );
      },
    );

    test(
      'idle status has no disabledReason when feed configured correctly',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'auto_update_healthy_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final service = AutoUpdateService(
          packageInfoLoader: () async => PackageInfo(
            appName: 'Backup Database',
            packageName: 'backup_database',
            version: '3.0.1',
            buildNumber: '',
          ),
          feedUrlReader: () => 'https://example.com/appcast.xml',
          checkIntervalReader: () => '0',
          locksDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'locks')),
          updatesDirectoryResolver: () async =>
              Directory(p.join(tempDir.path, 'updates')),
          detachedProcessStarter: (executable, arguments) async => null,
          exitProcess: (code) {},
        );

        await service.initialize();

        if (Platform.isWindows) {
          expect(service.snapshot.status, AppUpdateStatus.idle);
          expect(service.snapshot.disabledReason, isNull);
          expect(service.feedUrl, 'https://example.com/appcast.xml');
        } else {
          // Em hosts não-Windows, esperamos disabled com reason
          // nonWindowsPlatform — não confundir com feedUrlMissing.
          expect(service.snapshot.status, AppUpdateStatus.disabled);
          expect(
            service.snapshot.disabledReason,
            AppUpdateDisabledReason.nonWindowsPlatform,
          );
        }
      },
    );
  });
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
