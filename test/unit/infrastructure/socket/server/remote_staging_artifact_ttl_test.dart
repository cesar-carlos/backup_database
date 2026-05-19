import 'dart:io';

import 'package:backup_database/infrastructure/socket/server/remote_staging_artifact_ttl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('RemoteStagingArtifactTtl', () {
    test('isMtimeExpired respeita clock injetavel', () {
      final t0 = DateTime.utc(2026, 4, 1, 12);
      final ttl = RemoteStagingArtifactTtl(
        clock: () => t0.add(const Duration(hours: 25)),
      );
      expect(ttl.isMtimeExpired(t0), isTrue);
      expect(
        ttl.isMtimeExpired(t0.add(const Duration(hours: 1))),
        isFalse,
      );
    });

    test('isPathUnderRemoteStaging: primeiro segmento remote', () async {
      final tmp = await Directory.systemTemp.createTemp('ttl_path_');
      addTearDown(() => tmp.delete(recursive: true));
      final base = tmp.path;
      expect(
        isPathUnderRemoteStaging(
          base,
          p.join(base, 'remote', 'r1', 'a.bak'),
        ),
        isTrue,
      );
      expect(
        isPathUnderRemoteStaging(
          base,
          p.join(base, 'other', 'a.bak'),
        ),
        isFalse,
      );
    });
  });

  group('expiresAtForRunInStaging', () {
    test('resolve por pasta remote/<runId>', () async {
      final base = await Directory.systemTemp.createTemp('ttl_run_');
      addTearDown(() => base.delete(recursive: true));
      const runId = 'sch-1_00000000-0000-4000-8000-000000000001';
      final artifactDir = Directory(p.join(base.path, 'remote', runId));
      await artifactDir.create(recursive: true);
      final artifact = File(p.join(artifactDir.path, 'backup.bak'));
      final mtime = DateTime.utc(2026, 4, 19, 10);
      await artifact.writeAsString('x');
      await artifact.setLastModified(mtime);

      final ttl = RemoteStagingArtifactTtl();
      final expiresAt = await ttl.expiresAtForRunInStaging(base.path, runId);

      expect(
        expiresAt?.toUtc(),
        mtime.toUtc().add(const Duration(hours: 24)),
      );
    });

    test('retorna null quando staging nao existe', () async {
      final base = await Directory.systemTemp.createTemp('ttl_miss_');
      addTearDown(() => base.delete(recursive: true));
      final ttl = RemoteStagingArtifactTtl();
      final expiresAt = await ttl.expiresAtForRunInStaging(
        base.path,
        'sch-1_00000000-0000-4000-8000-000000000001',
      );
      expect(expiresAt, isNull);
    });
  });

  group('scheduleIdFromRunId', () {
    test('extrai scheduleId de runId valido', () {
      expect(
        RemoteStagingArtifactTtl.scheduleIdFromRunId(
          'sch-abc_00000000-0000-4000-8000-000000000001',
        ),
        'sch-abc',
      );
    });

    test('retorna null para formato invalido', () {
      expect(RemoteStagingArtifactTtl.scheduleIdFromRunId(''), isNull);
      expect(RemoteStagingArtifactTtl.scheduleIdFromRunId('short'), isNull);
    });
  });

  group('newestFileInTree', () {
    test('retorna o arquivo com lastModified mais recente', () async {
      final dir = await Directory.systemTemp.createTemp('ttl_tree_');
      final a = File(p.join(dir.path, 'a.txt'));
      final b = File(p.join(dir.path, 'b.txt'));
      await a.writeAsString('a');
      await b.writeAsString('b');
      await a.setLastModified(DateTime(2020));
      await b.setLastModified(DateTime(2021));
      addTearDown(() => dir.delete(recursive: true));

      final newest = await RemoteStagingArtifactTtl.newestFileInTree(dir);
      expect(newest?.path, b.path);
    });
  });
}
