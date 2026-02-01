import 'dart:io';

import 'dart:typed_data';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/utils/crc32.dart';
import 'package:backup_database/infrastructure/protocol/file_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FileChunker chunker;
  late Directory tempDir;

  setUp(() async {
    chunker = FileChunker();
    tempDir = await Directory.systemTemp.createTemp('file_chunker_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String tempPath(String name) => '${tempDir.path}/$name';

  group('FileChunk', () {
    test('toJson and fromJson round-trip', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final chunk = FileChunk(
        chunkIndex: 0,
        totalChunks: 1,
        data: data,
        checksum: 0x12345678,
      );
      final json = chunk.toJson();
      final decoded = FileChunk.fromJson(json);
      expect(decoded.chunkIndex, chunk.chunkIndex);
      expect(decoded.totalChunks, chunk.totalChunks);
      expect(decoded.data, orderedEquals(chunk.data));
      expect(decoded.checksum, chunk.checksum);
    });

    test('isValidChecksum true when checksum matches', () {
      final data = Uint8List.fromList([10, 20, 30]);
      final expectedCrc = Crc32.calculateUint8List(data);
      final chunk = FileChunk(
        chunkIndex: 0,
        totalChunks: 1,
        data: data,
        checksum: expectedCrc,
      );
      expect(chunk.isValidChecksum, isTrue);
    });

    test('isValidChecksum false when checksum does not match', () {
      final data = Uint8List.fromList([10, 20, 30]);
      final chunk = FileChunk(
        chunkIndex: 0,
        totalChunks: 1,
        data: data,
        checksum: 0,
      );
      expect(chunk.isValidChecksum, isFalse);
    });
  });

  group('FileChunker', () {
    test('chunkFile small file (< chunkSize) returns single chunk', () async {
      final path = tempPath('small.bin');
      final content = List<int>.generate(100, (i) => i);
      await File(path).writeAsBytes(content);
      final chunks = await chunker.chunkFile(path);
      expect(chunks.length, 1);
      expect(chunks[0].chunkIndex, 0);
      expect(chunks[0].totalChunks, 1);
      expect(chunks[0].data.length, 100);
      expect(chunks[0].data, orderedEquals(content));
      expect(chunks[0].isValidChecksum, isTrue);
    });

    test('chunkFile then assembleChunks reproduces file', () async {
      final path = tempPath('source.bin');
      final content = List<int>.generate(2000, (i) => i % 256);
      await File(path).writeAsBytes(content);
      final chunks = await chunker.chunkFile(path, 500);
      expect(chunks.length, 4);
      final outPath = tempPath('out.bin');
      await chunker.assembleChunks(chunks, outPath);
      final readBack = await File(outPath).readAsBytes();
      expect(readBack, orderedEquals(content));
    });

    test('chunkFile uses default chunkSize when not specified', () async {
      final path = tempPath('medium.bin');
      const size = SocketConfig.chunkSize + 100;
      final content = List<int>.filled(size, 42);
      await File(path).writeAsBytes(content);
      final chunks = await chunker.chunkFile(path);
      expect(chunks.length, 2);
      expect(chunks[0].data.length, SocketConfig.chunkSize);
      expect(chunks[1].data.length, 100);
    });

    test('assembleChunks throws when chunk checksum invalid', () async {
      final path = tempPath('source.bin');
      await File(path).writeAsBytes([1, 2, 3]);
      final chunks = await chunker.chunkFile(path);
      chunks[0] = FileChunk(
        chunkIndex: 0,
        totalChunks: 1,
        data: chunks[0].data,
        checksum: 0,
      );
      final outPath = tempPath('out.bin');
      expect(
        () => chunker.assembleChunks(chunks, outPath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('assembleChunks throws when chunk missing', () async {
      final path = tempPath('two.bin');
      await File(path).writeAsBytes(List<int>.filled(300, 1));
      final chunks = await chunker.chunkFile(path, 200);
      expect(chunks.length, 2);
      final incomplete = [chunks[0]];
      final outPath = tempPath('out.bin');
      expect(
        () => chunker.assembleChunks(incomplete, outPath),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('chunkFile throws when file does not exist', () async {
      expect(
        () => chunker.chunkFile(tempPath('nonexistent.bin')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('assembleChunks throws when chunks empty', () async {
      expect(
        () => chunker.assembleChunks([], tempPath('out.bin')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
