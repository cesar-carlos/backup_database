import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/utils/crc32.dart';
import 'package:backup_database/core/utils/logger_service.dart';

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

  Map<String, dynamic> toJson() {
    final base64Data = base64Encode(data);
    LoggerService.debug(
      '[FileChunk.toJson] Chunk $chunkIndex: ${data.length} bytes → Base64 ${base64Data.length} chars',
    );
    return <String, dynamic>{
      'chunkIndex': chunkIndex,
      'totalChunks': totalChunks,
      'data': base64Data,
      'checksum': checksum,
    };
  }

  factory FileChunk.fromJson(Map<String, dynamic> json) {
    final dataRaw = json['data'];
    LoggerService.debug(
      '[FileChunk.fromJson] Tipo de dataRaw: ${dataRaw.runtimeType}, valor: ${dataRaw.toString().substring(0, dataRaw.toString().length > 100 ? 100 : dataRaw.toString().length)}',
    );

    final Uint8List data;
    if (dataRaw is Uint8List) {
      data = dataRaw;
      LoggerService.debug(
        '[FileChunk.fromJson] Usando Uint8List direto: ${data.length} bytes',
      );
    } else if (dataRaw is String) {
      LoggerService.debug(
        '[FileChunk.fromJson] Decodificando String Base64 (${dataRaw.length} chars)',
      );
      data = base64Decode(dataRaw);
      LoggerService.debug(
        '[FileChunk.fromJson] Decodificado para ${data.length} bytes',
      );
    } else if (dataRaw is List<dynamic>) {
      LoggerService.debug(
        '[FileChunk.fromJson] Convertendo List<dynamic> (${dataRaw.length} elementos)',
      );
      data = Uint8List.fromList(dataRaw.cast<int>());
      LoggerService.debug(
        '[FileChunk.fromJson] Convertido para ${data.length} bytes',
      );
    } else {
      throw ArgumentError(
        'data must be Uint8List, String, or List<int>, got ${dataRaw.runtimeType}',
      );
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
    LoggerService.info(
      '[FileChunker.chunkFile] Processando arquivo: $filePath',
    );
    LoggerService.info(
      '[FileChunker.chunkFile] Chunk size: $useChunkSize bytes',
    );

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final bytes = await file.readAsBytes();
    final totalFileSize = bytes.length;
    LoggerService.info(
      '[FileChunker.chunkFile] Arquivo lido: $totalFileSize bytes',
    );

    final chunks = <FileChunk>[];
    final totalChunks = (bytes.length / useChunkSize).ceil();
    LoggerService.info(
      '[FileChunker.chunkFile] Serão criados $totalChunks chunks',
    );

    for (var i = 0; i < bytes.length; i += useChunkSize) {
      final end = (i + useChunkSize < bytes.length)
          ? i + useChunkSize
          : bytes.length;
      final chunkData = Uint8List.fromList(bytes.sublist(i, end));
      final checksum = Crc32.calculateUint8List(chunkData);

      final chunk = FileChunk(
        chunkIndex: chunks.length,
        totalChunks: totalChunks,
        data: chunkData,
        checksum: checksum,
      );
      chunks.add(chunk);

      LoggerService.debug(
        '[FileChunker.chunkFile] Chunk ${chunk.chunkIndex} criado: ${chunkData.length} bytes, checksum=$checksum',
      );
    }

    final totalChunkSize = chunks.fold<int>(0, (sum, c) => sum + c.data.length);
    LoggerService.info(
      '[FileChunker.chunkFile] ✓ $totalChunks chunks criados, total size: $totalChunkSize bytes',
    );

    return chunks;
  }

  Future<void> assembleChunks(List<FileChunk> chunks, String outputPath) async {
    LoggerService.info(
      '[FileChunker] Iniciando montagem de arquivo: $outputPath',
    );
    LoggerService.info('[FileChunker] Chunks recebidos: ${chunks.length}');

    if (chunks.isEmpty) {
      throw ArgumentError('chunks must not be empty');
    }
    final sorted = List<FileChunk>.from(chunks)
      ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    final totalChunks = sorted.first.totalChunks;
    if (sorted.length != totalChunks) {
      throw ArgumentError(
        'Missing chunks: expected $totalChunks, got ${sorted.length}',
      );
    }

    LoggerService.info('[FileChunker] Validando ${sorted.length} chunks...');
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
      LoggerService.info(
        '[FileChunker] Chunk $i: ${sorted[i].data.length} bytes, checksum válido',
      );
    }

    LoggerService.info('[FileChunker] Criando arquivo e escrevendo chunks...');
    final file = File(outputPath);
    final sink = file.openWrite();
    var totalBytes = 0;
    for (final chunk in sorted) {
      sink.add(chunk.data);
      totalBytes += chunk.data.length;
      LoggerService.debug(
        '[FileChunker] Escrito chunk ${chunk.chunkIndex}: ${chunk.data.length} bytes (total: $totalBytes)',
      );
    }

    LoggerService.info('[FileChunker] Flush do sink...');
    await sink.flush();
    LoggerService.info('[FileChunker] Fechando sink...');
    await sink.close();

    LoggerService.info('[FileChunker] Verificando arquivo final...');
    final fileSize = await file.length();
    LoggerService.info(
      '[FileChunker] Tamanho final do arquivo: $fileSize bytes (esperado: $totalBytes bytes)',
    );

    if (fileSize != totalBytes) {
      throw FileSystemException(
        'File size mismatch after assembly: expected $totalBytes bytes, got $fileSize bytes',
        outputPath,
      );
    }

    LoggerService.info('[FileChunker] ✓ Arquivo montado com sucesso!');
  }
}
