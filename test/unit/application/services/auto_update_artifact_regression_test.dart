import 'dart:io';

import 'package:backup_database/application/services/auto_update/app_update_artifact_store.dart';
import 'package:backup_database/application/services/auto_update/app_update_diagnostics_store.dart';
import 'package:backup_database/application/services/auto_update/app_update_global_lock.dart';
import 'package:backup_database/application/services/auto_update/app_update_install_context_store.dart';
import 'package:backup_database/application/services/auto_update/app_update_types.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

Future<T> _once<T>({
  required String label,
  required Future<T> Function() action,
}) => action();

void main() {
  test('old lock still belongs to a live updater', () async {
    final dir = await Directory.systemTemp.createTemp('update_lock_alive_');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/auto_update.lock')
        .writeAsString('pid=123\n');
    await file.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    final handle = await AppUpdateGlobalLock.tryAcquireGlobalLock(
      locksDir: dir,
      metadata: {},
      processAliveCheck: (_) => true,
    );
    expect(handle, isNull);
    expect(await file.readAsString(), 'pid=123\n');
  });

  for (final mode in ['valid', 'truncated', 'corrupt']) {
    test('download $mode publishes only verified installer', () async {
      final dir = await Directory.systemTemp.createTemp('update_artifact_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dio = Dio();
      addTearDown(() async {
        dio.close(force: true);
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final expected = [1, 2, 3, 4];
      final target = await File('${dir.path}/BackupDatabase-Setup-1.2.3.exe')
          .writeAsString('previous valid download');
      server.listen((request) async {
        request.response.add(
          mode == 'truncated'
              ? [1, 2]
              : mode == 'corrupt'
              ? [4, 3, 2, 1]
              : expected,
        );
        await request.response.close();
      });
      final store = AppUpdateArtifactStore(
        dio: dio,
        updatesDirectoryResolver: () async => dir,
        freeDiskSpaceProbe: (_) async => null,
        runWithRetry: _once,
        installContextStore: AppUpdateInstallContextStore(
          updatesDirectoryResolver: () async => dir,
        ),
        diagnosticsStore: AppUpdateDiagnosticsStore(
          updatesDirectoryResolver: () async => dir,
        ),
      );
      final operation = store.downloadInstaller(
        AppcastRelease(
          version: Version(1, 2, 3),
          publishedAt: DateTime(2026),
          title: 'Test',
          description: '',
          downloadUrl:
              'http://127.0.0.1:${server.port}/BackupDatabase-Setup-1.2.3.exe',
          fileSizeBytes: expected.length,
          sha256: sha256.convert(expected).toString(),
        ),
      );
      if (mode == 'valid') {
        expect(await (await operation).readAsBytes(), expected);
      } else {
        await expectLater(operation, throwsStateError);
        expect(await target.readAsString(), 'previous valid download');
      }
      expect(await File('${target.path}.part').exists(), isFalse);
    });
  }
}
