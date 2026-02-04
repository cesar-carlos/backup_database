import 'dart:io';

import 'dart:typed_data';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/utils/crc32.dart';

class FileChunk {
  const FileChunk({
    required this.chunkIndex,
    required this.totalChunks,
    required this.data,
    required this.checksum,
  });

  final int chunkIndex;
  final int totalChunks;
  final Uint8List data;
  final int checksum;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'chunkIndex': chunkIndex,
        'totalChunks': totalChunks,
        'data': data.toList(),
        'checksum': checksum,
      };

  factory FileChunk.fromJson(Map<String, dynamic> json) {
    final dataRaw = json['data'];
    final Uint8List data;
    if (dataRaw is Uint8List) {
      data = dataRaw;
    } else if (dataRaw is List<dynamic>) {
      data = Uint8List.fromList(dataRaw.cast<int>());
    } else {
      throw ArgumentError('data must be Uint8List or List<int>');
    }
    return FileChunk(
      chunkIndex: json['chunkIndex'] as int,
      totalChunks: json['totalChunks'] as int,
      data: data,
      checksum: json['checksum'] as int,
    );
  }

  bool get isValidChecksum => Crc32.calculateUint8List(data) == checksum;
}

class FileChunker {
  FileChunker({this.chunkSize = SocketConfig.chunkSize});

  final int chunkSize;

  Future<List<FileChunk>> chunkFile(String filePath, [int? size]) async {
    final useChunkSize = size ?? chunkSize;
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    final bytes = await file.readAsBytes();
    final chunks = <FileChunk>[];
    final totalChunks = (bytes.length / useChunkSize).ceil();
    for (var i = 0; i < bytes.length; i += useChunkSize) {
      final end = (i + useChunkSize < bytes.length) ? i + useChunkSize : bytes.length;
      final chunkData = Uint8List.fromList(bytes.sublist(i, end));
      final checksum = Crc32.calculateUint8List(chunkData);
      chunks.add(FileChunk(
        chunkIndex: chunks.length,
        totalChunks: totalChunks,
        data: chunkData,
        checksum: checksum,
      ));
    }
    return chunks;
  }

  Future<void> assembleChunks(List<FileChunk> chunks, String outputPath) async {
    if (chunks.isEmpty) {
      throw ArgumentError('chunks must not be empty');
    }
    final sorted = List<FileChunk>.from(chunks)..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    final totalChunks = sorted.first.totalChunks;
    if (sorted.length != totalChunks) {
      throw ArgumentError(
        'Missing chunks: expected $totalChunks, got ${sorted.length}',
      );
    }
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].chunkIndex != i) {
        throw ArgumentError('Duplicate or missing chunk index: $i');
      }
      if (!sorted[i].isValidChecksum) {
        throw FileSystemException(
          'Invalid checksum for chunk $i',
          outputPath,
        );
      }
    }
    final file = File(outputPath);
    final sink = file.openWrite();
    for (final chunk in sorted) {
      sink.add(chunk.data);
    }
    await sink.close();
  }
}
