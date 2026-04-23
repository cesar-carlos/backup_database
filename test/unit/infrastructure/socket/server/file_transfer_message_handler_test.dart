import 'dart:io';

import 'package:backup_database/domain/constants/transfer_lease.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/file_chunker.dart';
import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeLockService implements IFileTransferLockService {
  @override
  Future<void> cleanupExpiredLocks({
    Duration maxAge = const Duration(minutes: 30),
  }) async {}

  @override
  Future<bool> isLocked(String filePath) async => false;

  @override
  Future<void> releaseLock(String filePath) async {}

  @override
  Future<bool> tryAcquireLock(
    String filePath, {
    String owner = 'unknown',
    String? runId,
    Duration leaseTtl = kDefaultTransferLeaseTtl,
  }) async => true;
}

void main() {
  group('FileTransferMessageHandler startChunk', () {
    late Directory tempDir;
    late FileTransferMessageHandler handler;
    late File testFile;
    late Message requestBase;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ft_handler_');
      testFile = File(p.join(tempDir.path, 'sample.bin'));
      await testFile.writeAsBytes(List<int>.generate(35, (i) => i));

      handler = FileTransferMessageHandler(
        allowedBasePath: tempDir.path,
        lockService: _FakeLockService(),
        chunker: FileChunker(chunkSize: 10),
      );

      requestBase = createFileTransferStartRequestMessage(
        requestId: 1,
        filePath: 'sample.bin',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should send chunks from requested start chunk', () async {
      final messages = <Message>[];
      final request = createFileTransferStartRequestMessage(
        requestId: requestBase.header.requestId,
        filePath: 'sample.bin',
        startChunk: 2,
      );

      await handler.handle(
        'client-1',
        request,
        (_, message) async => messages.add(message),
      );

      final metadata = messages.firstWhere(isFileTransferStartMetadata);
      expect(getChunkSizeFromMetadata(metadata), 10);

      final chunkMessages = messages.where(isFileChunkMessage).toList();
      expect(chunkMessages.length, 2);
      final sentIndexes = chunkMessages
          .map(getFileChunkFromPayload)
          .map((c) => c.chunkIndex)
          .toList();
      expect(sentIndexes, [2, 3]);

      final progressMessages = messages
          .where(isFileTransferProgressMessage)
          .toList();
      final progressCurrent = progressMessages
          .map(getCurrentChunkFromProgress)
          .toList();
      expect(progressCurrent, [3, 4]);

      expect(messages.last.header.type, MessageType.fileTransferComplete);
    });

    test(
      'should send complete without chunks when start chunk is beyond total',
      () async {
        final messages = <Message>[];
        final request = createFileTransferStartRequestMessage(
          requestId: requestBase.header.requestId,
          filePath: 'sample.bin',
          startChunk: 99,
        );

        await handler.handle(
          'client-1',
          request,
          (_, message) async => messages.add(message),
        );

        final chunkMessages = messages.where(isFileChunkMessage).toList();
        final progressMessages = messages
            .where(isFileTransferProgressMessage)
            .toList();
        expect(chunkMessages, isEmpty);
        expect(progressMessages, isEmpty);
        expect(messages.any(isFileTransferStartMetadata), isTrue);
        expect(messages.last.header.type, MessageType.fileTransferComplete);
      },
    );

    test('should normalize negative start chunk to zero', () async {
      final messages = <Message>[];
      final request = createFileTransferStartRequestMessage(
        requestId: requestBase.header.requestId,
        filePath: 'sample.bin',
        startChunk: -3,
      );

      await handler.handle(
        'client-1',
        request,
        (_, message) async => messages.add(message),
      );

      final chunkMessages = messages.where(isFileChunkMessage).toList();
      expect(chunkMessages.length, 4);
      final firstChunk = getFileChunkFromPayload(chunkMessages.first);
      expect(firstChunk.chunkIndex, 0);
    });

    test('rejeita arquivo em remote/ com mtime fora do TTL (PR-4)', () async {
      final remoteDir = Directory(p.join(tempDir.path, 'remote', 'run-1'));
      await remoteDir.create(recursive: true);
      final stale = File(p.join(remoteDir.path, 'stale.bak'));
      await stale.writeAsBytes([1, 2, 3]);
      final old = DateTime.now().subtract(const Duration(hours: 25));
      await stale.setLastModified(old);

      final messages = <Message>[];
      final request = createFileTransferStartRequestMessage(
        requestId: 9,
        filePath: p.join('remote', 'run-1', 'stale.bak'),
      );
      await handler.handle(
        'c1',
        request,
        (_, m) async => messages.add(m),
      );

      final err = messages.firstWhere(
        (m) => m.header.type == MessageType.fileTransferError,
      );
      expect(getErrorCodeFromMessage(err), ErrorCode.artifactExpired);
    });
  });
}
