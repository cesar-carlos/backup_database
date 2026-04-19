import 'dart:io';

import 'package:backup_database/infrastructure/utils/staging_usage_measurer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('StagingUsageMeasurer', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'staging_usage_measurer_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns 0 when directory does not exist', () async {
      final size = await StagingUsageMeasurer.measure(
        p.join(tempDir.path, 'nonexistent'),
      );
      expect(size, 0);
    });

    test('returns 0 for empty directory', () async {
      final size = await StagingUsageMeasurer.measure(tempDir.path);
      expect(size, 0);
    });

    test('sums sizes of files at root', () async {
      await File(p.join(tempDir.path, 'a.txt')).writeAsString('AAA'); // 3 bytes
      await File(p.join(tempDir.path, 'b.txt')).writeAsString('BBBBB'); // 5

      final size = await StagingUsageMeasurer.measure(tempDir.path);
      expect(size, 8);
    });

    test('sums sizes recursively across subdirectories', () async {
      final sub = Directory(p.join(tempDir.path, 'remote', 'sched-1'));
      await sub.create(recursive: true);
      await File(p.join(tempDir.path, 'top.bin')).writeAsBytes(
        List<int>.filled(100, 0),
      );
      await File(p.join(sub.path, 'backup.zip')).writeAsBytes(
        List<int>.filled(250, 1),
      );

      final size = await StagingUsageMeasurer.measure(tempDir.path);
      expect(size, 350);
    });

    test('ignores empty directories (count zero added)', () async {
      await Directory(p.join(tempDir.path, 'empty1')).create();
      await Directory(p.join(tempDir.path, 'empty2', 'nested')).create(
        recursive: true,
      );

      final size = await StagingUsageMeasurer.measure(tempDir.path);
      expect(size, 0);
    });

    test('large file count is summed correctly', () async {
      for (var i = 0; i < 50; i++) {
        await File(p.join(tempDir.path, 'f$i.txt')).writeAsString('xx'); // 2
      }
      final size = await StagingUsageMeasurer.measure(tempDir.path);
      expect(size, 100);
    });
  });
}
