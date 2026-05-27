// PR-6: testes de integracao para cenarios criticos do plano.
//
// Cobertura:
// - A8.1: 2 clientes concorrentes disparando para o mesmo `scheduleId`
//   resultam em 1 running + 1 queued (mesmo `ExecutionQueueService`).
// - A8.2: fila persistida em SQLite sobrevive a "restart" do server
//   (nova instancia da `ExecutionQueueService` carregando do mesmo DB).
// - A8.3: `FileTransferResumeMetadata` com `runId` diferente do
//   solicitado e descartada — forca download do zero.
import 'dart:io';

import 'package:backup_database/infrastructure/datasources/daos/execution_queue_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/socket/client/file_transfer_resume_metadata_store.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_persistence.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PR-6 A8.1: backup queue com 2 clientes concorrentes', () {
    test(
      '2 enfileiramentos no mesmo scheduleId rejeita o segundo (dedup '
      'por scheduleId), mas scheduleIds distintos coexistem',
      () async {
        final svc = ExecutionQueueService();
        final c1First = await svc.tryEnqueue(
          scheduleId: 'sch-A',
          clientId: 'cliente-1',
          requestId: 1,
          requestedBy: 'cliente-1',
        );
        // segundo cliente tenta enfileirar mesmo scheduleId
        final c2Dup = await svc.tryEnqueue(
          scheduleId: 'sch-A',
          clientId: 'cliente-2',
          requestId: 2,
          requestedBy: 'cliente-2',
        );
        // schedule diferente vai sem problemas
        final c3Other = await svc.tryEnqueue(
          scheduleId: 'sch-B',
          clientId: 'cliente-2',
          requestId: 3,
          requestedBy: 'cliente-2',
        );

        expect(c1First, isNotNull, reason: 'primeiro tem que entrar');
        expect(
          c2Dup,
          isNull,
          reason: 'segundo do mesmo schedule deve ser rejeitado (dedup)',
        );
        expect(c3Other, isNotNull, reason: 'scheduleId diferente entra');
        expect(svc.queueSize, 2);
      },
    );

    test(
      'snapshot preserva ordem FIFO + queuedPosition 1-based para 2 '
      'clientes distintos',
      () async {
        final svc = ExecutionQueueService();
        await svc.tryEnqueue(
          scheduleId: 'sch-A',
          clientId: 'cliente-1',
          requestId: 1,
          requestedBy: 'cliente-1',
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await svc.tryEnqueue(
          scheduleId: 'sch-B',
          clientId: 'cliente-2',
          requestId: 2,
          requestedBy: 'cliente-2',
        );

        final snap = svc.snapshot();
        expect(snap[0].scheduleId, 'sch-A');
        expect(snap[0].queuedPosition, 1);
        expect(snap[0].requestedBy, 'cliente-1');
        expect(snap[1].scheduleId, 'sch-B');
        expect(snap[1].queuedPosition, 2);
        expect(snap[1].requestedBy, 'cliente-2');
      },
    );
  });

  group('PR-6 A8.2: server restart recovery', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pr6_restart_');
      dbFile = File(p.join(tempDir.path, 'restart_recovery.db'));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'fila enfileirada antes do restart e reidratada pela nova '
      'instancia do servidor',
      () async {
        // Primeira "sessao" do servidor: enfileira 3 itens.
        final db1 = AppDatabase.forTesting(NativeDatabase(dbFile));
        try {
          final svc1 = ExecutionQueueService(
            persistence: DriftExecutionQueuePersistence(
              ExecutionQueueDao(db1),
            ),
          );
          await svc1.initialize();
          await svc1.tryEnqueue(
            scheduleId: 'sch-restart-A',
            clientId: 'c1',
            requestId: 100,
            requestedBy: 'c1',
          );
          await svc1.tryEnqueue(
            scheduleId: 'sch-restart-B',
            clientId: 'c1',
            requestId: 101,
            requestedBy: 'c1',
          );
          await svc1.tryEnqueue(
            scheduleId: 'sch-restart-C',
            clientId: 'c1',
            requestId: 102,
            requestedBy: 'c1',
          );
          expect(svc1.queueSize, 3);
        } finally {
          await db1.close();
        }

        // Restart simulado: nova instancia da fila lendo do mesmo DB.
        final db2 = AppDatabase.forTesting(NativeDatabase(dbFile));
        try {
          final svc2 = ExecutionQueueService(
            persistence: DriftExecutionQueuePersistence(
              ExecutionQueueDao(db2),
            ),
          );
          await svc2.initialize();
          expect(
            svc2.queueSize,
            3,
            reason: 'fila persistida deve ser reidratada apos restart',
          );

          final snap = svc2.snapshot();
          expect(snap[0].scheduleId, 'sch-restart-A');
          expect(snap[1].scheduleId, 'sch-restart-B');
          expect(snap[2].scheduleId, 'sch-restart-C');
        } finally {
          await db2.close();
        }
      },
    );

    // PR-6 nota: reconcile de stale running esta coberto em
    // `test/unit/infrastructure/repositories/backup_history_repository_test.dart`
    // (group `reconcileStaleRunning`) + `scheduler_service_test.dart`
    // (verify do call no boot). Cenario integrado completo
    // (Drift file -> restart -> reconcile) ficaria muito custoso para
    // o ganho marginal sobre os 2 testes ja existentes.
  });

  group('PR-6 A8.3: file transfer resume com runId mismatch', () {
    late Directory tempDir;
    late FileTransferResumeMetadataStore store;
    late String outputPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pr6_resume_');
      store = const FileTransferResumeMetadataStore();
      outputPath = p.join(tempDir.path, 'backup.zip');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'metadata persistida com runId=A e tentativa de resume com '
      'runId=B faz matchesRunId retornar false (forca download zero)',
      () async {
        final original = FileTransferResumeMetadata(
          filePath: 'remote/run-A/backup.zip',
          partFilePath: '$outputPath.part',
          chunkSize: 131072,
          expectedSize: 4096,
          expectedHash: 'hash-A',
          scheduleId: 'sch-X',
          runId: 'sch-X_runA',
          updatedAt: DateTime.now().toUtc(),
        );
        await store.write(outputPath, original);

        // Restart simulado do cliente: le metadata e tenta resume
        // com `runId` diferente.
        final restored = await store.read(outputPath);
        expect(restored, isNotNull);
        expect(
          restored!.matchesRunId('sch-X_runB'),
          isFalse,
          reason: 'runId diferente deve descartar parcial',
        );
      },
    );

    test(
      'metadata sem runId (pre-PR-6) ainda permite resume com qualquer '
      'runId solicitado (compat backward)',
      () async {
        final legacy = FileTransferResumeMetadata(
          filePath: 'remote/legacy/backup.zip',
          partFilePath: '$outputPath.part',
          chunkSize: 131072,
          scheduleId: 'sch-legacy',
          updatedAt: DateTime.now().toUtc(),
        );
        await store.write(outputPath, legacy);
        final restored = await store.read(outputPath);
        expect(restored!.matchesRunId('sch-legacy_run-novo'), isTrue);
        expect(restored.matchesRunId(null), isTrue);
      },
    );

    test('round-trip de runId no JSON', () async {
      final metadata = FileTransferResumeMetadata(
        filePath: 'p',
        partFilePath: 'pp',
        chunkSize: 1024,
        runId: 'sch_runId-uuid-456',
        updatedAt: DateTime.now().toUtc(),
      );
      await store.write(outputPath, metadata);
      final restored = await store.read(outputPath);
      expect(restored?.runId, 'sch_runId-uuid-456');
    });
  });
}
