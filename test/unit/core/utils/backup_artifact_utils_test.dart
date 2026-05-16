import 'dart:io';

import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupArtifactUtils.safeDeletePartial', () {
    test('removes an existing file', () async {
      final dir = await Directory.systemTemp.createTemp('bau_file_');
      try {
        final f = File('${dir.path}/partial.bak');
        await f.writeAsBytes([1]);
        await BackupArtifactUtils.safeDeletePartial(f.path);
        expect(await f.exists(), isFalse);
      } finally {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('removes an existing directory recursively', () async {
      final root = await Directory.systemTemp.createTemp('bau_dir_');
      try {
        await File('${root.path}/a.dat').writeAsBytes([2]);
        final nested = Directory('${root.path}/n');
        await nested.create();
        await File('${nested.path}/b.dat').writeAsBytes([3]);
        await BackupArtifactUtils.safeDeletePartial(root.path);
        expect(await root.exists(), isFalse);
      } finally {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      }
    });

    test('does not throw when path is missing', () async {
      final p =
          '${Directory.systemTemp.path}/missing_${DateTime.now().microsecondsSinceEpoch}';
      await expectLater(
        BackupArtifactUtils.safeDeletePartial(p),
        completes,
      );
    });
  });

  group('BackupArtifactUtils.waitForStableFile', () {
    const fastInitial = Duration.zero;
    const fastPoll = Duration(milliseconds: 15);
    const fastStabilize = Duration(milliseconds: 10);
    const fastMax = Duration(seconds: 3);

    test('returns true when file is non-empty and size stabilizes', () async {
      final dir = await Directory.systemTemp.createTemp('bau_stable_');
      try {
        final f = File('${dir.path}/out.bak');
        await f.writeAsBytes([9, 9, 9]);
        final ok = await BackupArtifactUtils.waitForStableFile(
          f,
          initialDelay: fastInitial,
          pollInterval: fastPoll,
          stabilizeDelay: fastStabilize,
          maxWait: fastMax,
        );
        expect(ok, isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns false when file stays empty', () async {
      final dir = await Directory.systemTemp.createTemp('bau_empty_');
      try {
        final f = File('${dir.path}/empty.bak');
        await f.create();
        final ok = await BackupArtifactUtils.waitForStableFile(
          f,
          initialDelay: fastInitial,
          pollInterval: fastPoll,
          stabilizeDelay: fastStabilize,
          maxWait: const Duration(milliseconds: 120),
        );
        expect(ok, isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns false when file does not exist', () async {
      final f = File(
        '${Directory.systemTemp.path}/nope_${DateTime.now().microsecondsSinceEpoch}',
      );
      final ok = await BackupArtifactUtils.waitForStableFile(
        f,
        initialDelay: fastInitial,
        pollInterval: fastPoll,
        stabilizeDelay: fastStabilize,
        maxWait: const Duration(milliseconds: 80),
      );
      expect(ok, isFalse);
    });
  });
}
