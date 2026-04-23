import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';
import 'package:backup_database/infrastructure/socket/server/diagnostics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/diagnostics_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubProvider implements DiagnosticsProvider {
  DiagnosticsOutcome<RunLogsData>? logsOutcome;
  DiagnosticsOutcome<RunErrorData>? errorOutcome;
  DiagnosticsOutcome<ArtifactMetadataData>? metaOutcome;
  DiagnosticsOutcome<CleanupStagingData>? cleanupOutcome;

  int logsCalls = 0;
  int errorCalls = 0;
  int metaCalls = 0;
  int cleanupCalls = 0;

  @override
  Future<DiagnosticsOutcome<RunLogsData>> getRunLogs(
    String runId, {
    int? maxLines,
  }) async {
    logsCalls++;
    return logsOutcome ?? DiagnosticsOutcome.notFound();
  }

  @override
  Future<DiagnosticsOutcome<RunErrorData>> getRunErrorDetails(String runId) async {
    errorCalls++;
    return errorOutcome ?? DiagnosticsOutcome.notFound();
  }

  @override
  Future<DiagnosticsOutcome<ArtifactMetadataData>> getArtifactMetadata(
    String runId,
  ) async {
    metaCalls++;
    return metaOutcome ?? DiagnosticsOutcome.notFound();
  }

  @override
  Future<DiagnosticsOutcome<CleanupStagingData>> cleanupStaging(String runId) async {
    cleanupCalls++;
    return cleanupOutcome ?? DiagnosticsOutcome.notFound();
  }
}

void main() {
  late _StubProvider provider;
  late DiagnosticsMessageHandler handler;
  late List<Message> sent;

  Future<void> sendToClient(String _, Message m) async {
    sent.add(m);
  }

  setUp(() {
    provider = _StubProvider();
    handler = DiagnosticsMessageHandler(
      provider: provider,
      clock: () => DateTime.utc(2026, 4, 19, 12),
    );
    sent = [];
  });

  group('getRunLogs', () {
    test('responde com lines do provider', () async {
      provider.logsOutcome = DiagnosticsOutcome.found(
        const RunLogsData(lines: ['log1', 'log2'], truncated: true),
      );
      final req = createGetRunLogsRequest(runId: 'r1', maxLines: 100);
      await handler.handle('c1', req, sendToClient);

      final resp = sent.single;
      expect(resp.header.type, MessageType.getRunLogsResponse);
      expect(resp.payload['runId'], 'r1');
      expect(resp.payload['lines'] as List, ['log1', 'log2']);
      expect(resp.payload['truncated'], isTrue);
      expect(resp.payload['totalLines'], 2);
    });

    test('runId vazio -> error', () async {
      final bad = Message(
        header: MessageHeader(
          type: MessageType.getRunLogsRequest,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{'runId': ''},
        checksum: 0,
      );
      await handler.handle('c1', bad, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.invalidRequest);
    });

    test('not-found do provider -> error fileNotFound', () async {
      // logsOutcome = null -> notFound
      final req = createGetRunLogsRequest(runId: 'r-nope');
      await handler.handle('c1', req, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.fileNotFound);
    });
  });

  group('getRunErrorDetails', () {
    test('found=true com errorMessage e errorCode', () async {
      provider.errorOutcome = DiagnosticsOutcome.found(
        const RunErrorData(
          errorMessage: 'banco caiu',
          errorCode: ErrorCode.ioError,
          stackTrace: 'at line X',
        ),
      );
      final req = createGetRunErrorDetailsRequest(runId: 'r1');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.header.type, MessageType.getRunErrorDetailsResponse);
      expect(resp.payload['found'], isTrue);
      expect(resp.payload['errorMessage'], 'banco caiu');
      expect(resp.payload['errorCode'], 'IO_ERROR');
      expect(resp.payload['stackTrace'], 'at line X');
      expect(resp.payload['statusCode'], 200);
    });

    test('not-found vira response found=false (NAO error)', () async {
      // Diferente do getRunLogs: notFound aqui e resposta valida
      // (execucao pode nao ter falhado). Cliente recebe found=false.
      final req = createGetRunErrorDetailsRequest(runId: 'r-x');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.header.type, MessageType.getRunErrorDetailsResponse);
      expect(resp.payload['found'], isFalse);
      expect(resp.payload['statusCode'], 404);
    });
  });

  group('getArtifactMetadata', () {
    test('found com size+hash+expiresAt', () async {
      final expires = DateTime.utc(2026, 5);
      provider.metaOutcome = DiagnosticsOutcome.found(
        ArtifactMetadataData(
          sizeBytes: 1024,
          hashAlgorithm: 'sha256',
          hashValue: 'abc123',
          stagingPath: '/staging/r1.bak',
          expiresAt: expires,
        ),
      );
      final req = createGetArtifactMetadataRequest(runId: 'r1');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.payload['sizeBytes'], 1024);
      expect(resp.payload['hashAlgorithm'], 'sha256');
      expect(resp.payload['hashValue'], 'abc123');
      expect(resp.payload['stagingPath'], '/staging/r1.bak');
      expect(resp.payload['expiresAt'], expires.toIso8601String());
    });

    test('not-found vira response found=false (NAO error)', () async {
      final req = createGetArtifactMetadataRequest(runId: 'r-x');
      await handler.handle('c1', req, sendToClient);
      expect(sent.single.payload['found'], isFalse);
      expect(sent.single.payload['statusCode'], 404);
    });

    test('artifactExpired vira error 410 (nao found=false)', () async {
      provider.metaOutcome = DiagnosticsOutcome.artifactExpired();
      final req = createGetArtifactMetadataRequest(runId: 'r1');
      await handler.handle('c1', req, sendToClient);
      expect(sent.single.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.artifactExpired);
      expect(
        getStatusCodeFromMessage(sent.single),
        StatusCodes.gone,
      );
    });
  });

  group('cleanupStaging', () {
    test('cleaned=true com bytesFreed', () async {
      provider.cleanupOutcome = DiagnosticsOutcome.found(
        const CleanupStagingData(
          cleaned: true,
          bytesFreed: 4096,
          message: 'limpo',
        ),
      );
      final req = createCleanupStagingRequest(runId: 'r1');
      await handler.handle('c1', req, sendToClient);
      final resp = sent.single;
      expect(resp.payload['cleaned'], isTrue);
      expect(resp.payload['bytesFreed'], 4096);
    });

    test('not-found vira response cleaned=false (NAO error)', () async {
      final req = createCleanupStagingRequest(runId: 'r-x');
      await handler.handle('c1', req, sendToClient);
      expect(sent.single.payload['cleaned'], isFalse);
    });

    test('idempotencyKey: 2a chamada reusa cache', () async {
      provider.cleanupOutcome = DiagnosticsOutcome.found(
        const CleanupStagingData(cleaned: true, bytesFreed: 100),
      );
      final req = createCleanupStagingRequest(
        runId: 'r1',
        idempotencyKey: 'idem-clean',
      );
      await handler.handle('c1', req, sendToClient);
      await handler.handle('c1', req, sendToClient);
      expect(provider.cleanupCalls, 1);
      expect(sent, hasLength(2));
    });
  });

  group('NotConfiguredDiagnosticsProvider default', () {
    test('todas operacoes retornam notFound', () async {
      handler = DiagnosticsMessageHandler(
        clock: () => DateTime.utc(2026),
      );
      // getRunLogs -> error
      await handler.handle(
        'c1',
        createGetRunLogsRequest(runId: 'r'),
        sendToClient,
      );
      expect(getErrorCodeFromMessage(sent.last), ErrorCode.fileNotFound);

      // getRunErrorDetails -> response found=false
      await handler.handle(
        'c1',
        createGetRunErrorDetailsRequest(runId: 'r'),
        sendToClient,
      );
      expect(sent.last.payload['found'], isFalse);

      // getArtifactMetadata -> response found=false
      await handler.handle(
        'c1',
        createGetArtifactMetadataRequest(runId: 'r'),
        sendToClient,
      );
      expect(sent.last.payload['found'], isFalse);

      // cleanupStaging -> response cleaned=false
      await handler.handle(
        'c1',
        createCleanupStagingRequest(runId: 'r'),
        sendToClient,
      );
      expect(sent.last.payload['cleaned'], isFalse);
    });
  });

  group('outros tipos', () {
    test('ignora mensagem nao-relacionada (no-op)', () async {
      final unrelated = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: const <String, dynamic>{},
        checksum: 0,
      );
      await handler.handle('c1', unrelated, sendToClient);
      expect(sent, isEmpty);
    });
  });
}
