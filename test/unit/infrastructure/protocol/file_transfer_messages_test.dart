import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('file_transfer_messages', () {
    test('metadata message should include chunkSize when provided', () {
      final message = createFileTransferStartMetadataMessage(
        requestId: 10,
        fileName: 'backup.zip',
        fileSize: 1024,
        totalChunks: 8,
        chunkSize: 128,
      );

      expect(message.payload['chunkSize'], 128);
      expect(getChunkSizeFromMetadata(message), 128);
    });

    test('getChunkSizeFromMetadata should return null when absent', () {
      final message = createFileTransferStartMetadataMessage(
        requestId: 11,
        fileName: 'backup.zip',
        fileSize: 1024,
        totalChunks: 8,
      );

      expect(getChunkSizeFromMetadata(message), isNull);
    });

    test('getStartChunkFromRequest should return provided start chunk', () {
      final message = createFileTransferStartRequestMessage(
        requestId: 12,
        filePath: 'remote/backup.zip',
        startChunk: 4,
      );

      expect(getStartChunkFromRequest(message), 4);
    });

    test('getStartChunkFromRequest should default to zero', () {
      final message = createFileTransferStartRequestMessage(
        requestId: 13,
        filePath: 'remote/backup.zip',
      );

      expect(getStartChunkFromRequest(message), 0);
    });
  });
}
