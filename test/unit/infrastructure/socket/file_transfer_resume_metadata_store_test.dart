import 'dart:io';

import 'package:backup_database/infrastructure/socket/client/file_transfer_resume_metadata_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FileTransferResumeMetadataStore', () {
    late Directory tempDir;
    late FileTransferResumeMetadataStore store;
    late String outputPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resume_meta_');
      store = const FileTransferResumeMetadataStore();
      outputPath = p.join(tempDir.path, 'backup.zip');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('write and read should preserve metadata', () async {
      final now = DateTime.now().toUtc();
      final metadata = FileTransferResumeMetadata(
        filePath: 'remote/backup.zip',
        partFilePath: '$outputPath.part',
        chunkSize: 131072,
        expectedSize: 2048,
        expectedHash: 'abc123',
        scheduleId: 'schedule-1',
        updatedAt: now,
      );

      await store.write(outputPath, metadata);
      final restored = await store.read(outputPath);

      expect(restored, isNotNull);
      expect(restored!.filePath, metadata.filePath);
      expect(restored.partFilePath, metadata.partFilePath);
      expect(restored.chunkSize, metadata.chunkSize);
      expect(restored.expectedSize, metadata.expectedSize);
      expect(restored.expectedHash, metadata.expectedHash);
      expect(restored.isCompressed, metadata.isCompressed);
      expect(restored.scheduleId, metadata.scheduleId);
      expect(restored.updatedAt.toIso8601String(), now.toIso8601String());
    });

    test('read should return null for missing file', () async {
      final restored = await store.read(outputPath);
      expect(restored, isNull);
    });

    test('read should return null for invalid json', () async {
      final metadataFile = File('$outputPath.part.meta.json');
      await metadataFile.writeAsString('{invalid_json', flush: true);

      final restored = await store.read(outputPath);
      expect(restored, isNull);
    });

    test('delete should remove metadata file', () async {
      final metadata = FileTransferResumeMetadata(
        filePath: 'remote/backup.zip',
        partFilePath: '$outputPath.part',
        chunkSize: 131072,
        updatedAt: DateTime.now().toUtc(),
      );
      await store.write(outputPath, metadata);

      await store.delete(outputPath);

      final metadataFile = File('$outputPath.part.meta.json');
      expect(await metadataFile.exists(), isFalse);
    });

    group('PR-6: runId em FileTransferResumeMetadata', () {
      test('write + read preserva runId', () async {
        final metadata = FileTransferResumeMetadata(
          filePath: 'remote/run-1/backup.zip',
          partFilePath: '$outputPath.part',
          chunkSize: 131072,
          scheduleId: 'schedule-1',
          runId: 'schedule-1_abc123',
          updatedAt: DateTime.now().toUtc(),
        );
        await store.write(outputPath, metadata);
        final restored = await store.read(outputPath);
        expect(restored?.runId, 'schedule-1_abc123');
      });

      test('matchesRunId: ambos nulos -> permite resume (compat pre-PR-6)', () {
        final metadata = FileTransferResumeMetadata(
          filePath: 'p',
          partFilePath: 'pp',
          chunkSize: 1,
          updatedAt: DateTime.now().toUtc(),
        );
        expect(metadata.matchesRunId(null), isTrue);
        expect(metadata.matchesRunId(''), isTrue);
      });

      test('matchesRunId: requested presente, metadata nulo -> permite '
          '(metadata legado nao bloqueia resume novo)', () {
        final metadata = FileTransferResumeMetadata(
          filePath: 'p',
          partFilePath: 'pp',
          chunkSize: 1,
          updatedAt: DateTime.now().toUtc(),
        );
        expect(metadata.matchesRunId('run-novo'), isTrue);
      });

      test('matchesRunId: metadata presente, requested nulo -> permite '
          '(cliente nao identificou runId; tolera)', () {
        final metadata = FileTransferResumeMetadata(
          filePath: 'p',
          partFilePath: 'pp',
          chunkSize: 1,
          runId: 'run-A',
          updatedAt: DateTime.now().toUtc(),
        );
        expect(metadata.matchesRunId(null), isTrue);
      });

      test('matchesRunId: ambos presentes e iguais -> permite', () {
        final metadata = FileTransferResumeMetadata(
          filePath: 'p',
          partFilePath: 'pp',
          chunkSize: 1,
          runId: 'run-A',
          updatedAt: DateTime.now().toUtc(),
        );
        expect(metadata.matchesRunId('run-A'), isTrue);
      });

      test('matchesRunId: ambos presentes e diferentes -> bloqueia '
          '(parcial pertence a outra execucao)', () {
        final metadata = FileTransferResumeMetadata(
          filePath: 'p',
          partFilePath: 'pp',
          chunkSize: 1,
          runId: 'run-A',
          updatedAt: DateTime.now().toUtc(),
        );
        expect(metadata.matchesRunId('run-B'), isFalse);
      });
    });
  });
}
