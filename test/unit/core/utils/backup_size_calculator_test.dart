import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/backup_size_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupSizeCalculator.bytesOfFile', () {
    test('returns failure when path does not exist', () async {
      final result = await BackupSizeCalculator.bytesOfFile(
        '${Directory.systemTemp.path}/no_such_backup_${DateTime.now().microsecondsSinceEpoch}.bak',
      );
      expect(result.isError(), isTrue);
      final Object? ex = result.exceptionOrNull();
      expect(ex, isA<BackupFailure>());
    });

    test('returns byte length of existing file', () async {
      final dir = await Directory.systemTemp.createTemp('bsc_file_');
      try {
        final f = File('${dir.path}/x.dat');
        await f.writeAsBytes(List<int>.filled(37, 7));
        final result = await BackupSizeCalculator.bytesOfFile(f.path);
        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 37);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('BackupSizeCalculator.bytesOfDirectoryTree', () {
    test('returns failure when directory does not exist', () async {
      final result = await BackupSizeCalculator.bytesOfDirectoryTree(
        '${Directory.systemTemp.path}/no_such_dir_${DateTime.now().microsecondsSinceEpoch}',
      );
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<BackupFailure>());
    });

    test('sums all file bytes recursively', () async {
      final root = await Directory.systemTemp.createTemp('bsc_tree_');
      try {
        await File('${root.path}/a.txt').writeAsBytes([1, 2]);
        final nested = Directory('${root.path}/n');
        await nested.create();
        await File('${nested.path}/b.txt').writeAsBytes([3, 4, 5]);
        final result = await BackupSizeCalculator.bytesOfDirectoryTree(
          root.path,
        );
        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 5);
      } finally {
        await root.delete(recursive: true);
      }
    });
  });

  group('BackupSizeCalculator.sumBytesInDirectoryShallow', () {
    test('returns 0 when directory missing', () async {
      final n = await BackupSizeCalculator.sumBytesInDirectoryShallow(
        Directory(
          '${Directory.systemTemp.path}/missing_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      expect(n, 0);
    });

    test('counts only immediate files not subdirectories', () async {
      final root = await Directory.systemTemp.createTemp('bsc_shallow_');
      try {
        await File('${root.path}/top.dat').writeAsBytes([9, 9]);
        final nested = Directory('${root.path}/inner');
        await nested.create();
        await File('${nested.path}/hidden.dat').writeAsBytes([1, 1, 1, 1]);
        final n = await BackupSizeCalculator.sumBytesInDirectoryShallow(root);
        expect(n, 2);
      } finally {
        await root.delete(recursive: true);
      }
    });
  });

  group('BackupSizeCalculator.bytesOfExistingFiles', () {
    test('returns failure if any path missing', () async {
      final dir = await Directory.systemTemp.createTemp('bsc_multi_');
      try {
        final ok = File('${dir.path}/ok.dat');
        await ok.writeAsBytes([5]);
        final result = await BackupSizeCalculator.bytesOfExistingFiles([
          ok.path,
          '${dir.path}/missing.dat',
        ]);
        expect(result.isError(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('sums multiple existing files', () async {
      final dir = await Directory.systemTemp.createTemp('bsc_multi_ok_');
      try {
        await File('${dir.path}/a.dat').writeAsBytes([2]);
        await File('${dir.path}/b.dat').writeAsBytes([3, 3]);
        final result = await BackupSizeCalculator.bytesOfExistingFiles([
          '${dir.path}/a.dat',
          '${dir.path}/b.dat',
        ]);
        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 3);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
