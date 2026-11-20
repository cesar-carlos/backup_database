import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _File extends Mock implements File {}

void main() {
  const blockSize = 4 * 1024 * 1024;
  for (final size in [0, 23, blockSize, blockSize + 17]) {
    test(
      'should hash $size bytes independently of read fragmentation',
      () async {
        final data = Uint8List.fromList(
          List<int>.generate(size, (i) => i % 251),
        );
        final digests = <int>[];
        for (var offset = 0; offset < size; offset += blockSize) {
          final end = offset + blockSize < size ? offset + blockSize : size;
          digests.addAll(
            sha256.convert(Uint8List.sublistView(data, offset, end)).bytes,
          );
        }
        final file = _File();
        Stream<List<int>> fragments() async* {
          for (var offset = 0; offset < size; offset += 65521) {
            final end = offset + 65521 < size ? offset + 65521 : size;
            yield Uint8List.sublistView(data, offset, end);
          }
        }

        when(file.openRead).thenAnswer((_) => fragments());
        expect(
          await FileHashUtils.computeDropboxContentHash(file),
          sha256.convert(digests).toString(),
        );
      },
    );
  }
}
