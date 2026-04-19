import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/protocol/response_envelope.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wrapSuccessResponse helper (F0.5)', () {
    test('adiciona success: true e statusCode default 200', () {
      final wrapped = wrapSuccessResponse(<String, dynamic>{
        'foo': 'bar',
        'count': 42,
      });
      expect(wrapped['success'], isTrue);
      expect(wrapped['statusCode'], 200);
      expect(wrapped['foo'], 'bar');
      expect(wrapped['count'], 42);
    });

    test('respeita statusCode customizado (ex.: 202 accepted)', () {
      final wrapped = wrapSuccessResponse(
        <String, dynamic>{'runId': 'abc'},
        statusCode: StatusCodes.accepted,
      );
      expect(wrapped['statusCode'], 202);
      expect(wrapped['success'], isTrue);
    });

    test('campos do payload original sobrescrevem os do envelope', () {
      // Cenario raro mas defensivo: se alguem passar {success: false}
      // como data, o envelope continua emitindo true (consistencia
      // semantica — o helper e para SUCESSO).
      // Aqui validamos que a ordem do spread coloca data DEPOIS dos
      // defaults — ou seja, data prevalece. Decisao consciente: helper
      // confia no chamador.
      final wrapped = wrapSuccessResponse(<String, dynamic>{
        'success': false, // override ruim; chamador e responsavel
        'extra': 'x',
      });
      expect(wrapped['success'], isFalse);
      expect(wrapped['extra'], 'x');
    });
  });

  group('getSuccessFromMessage', () {
    test('le success bool quando presente', () {
      final msg = createCapabilitiesResponseMessage(
        requestId: 1,
        protocolVersion: 1,
        wireVersion: 1,
        supportsRunId: true,
        supportsResume: true,
        supportsArtifactRetention: false,
        supportsChunkAck: false,
        supportsExecutionQueue: false,
        chunkSize: 65536,
        compression: 'gzip',
        serverTimeUtc: DateTime.utc(2026, 4, 19),
      );
      expect(getSuccessFromMessage(msg), isTrue);
    });

    test('retorna null em payload v1 sem campo success', () {
      final msg = Message(
        header: MessageHeader(
          type: MessageType.capabilitiesResponse,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{
          'protocolVersion': 1, // sem success/statusCode
        },
        checksum: 0,
      );
      expect(getSuccessFromMessage(msg), isNull);
    });

    test('retorna null quando success nao e bool (defesa contra payload corrompido)',
        () {
      final msg = Message(
        header: MessageHeader(
          type: MessageType.capabilitiesResponse,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{
          'success': 'true', // string em vez de bool
        },
        checksum: 0,
      );
      expect(getSuccessFromMessage(msg), isNull);
    });
  });

  group('invariante: todos os response factories aplicam o envelope', () {
    // Garante que TODOS os 7 handlers de inspecao migrados emitem
    // success + statusCode. Se alguem adicionar novo handler de
    // resposta sem aplicar wrapSuccessResponse, o teste falha
    // imediatamente.

    test('capabilitiesResponse', () {
      final msg = createCapabilitiesResponseMessage(
        requestId: 1,
        protocolVersion: 1,
        wireVersion: 1,
        supportsRunId: true,
        supportsResume: true,
        supportsArtifactRetention: false,
        supportsChunkAck: false,
        supportsExecutionQueue: false,
        chunkSize: 1024,
        compression: 'gzip',
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
    });

    test('healthResponse', () {
      final msg = createHealthResponseMessage(
        requestId: 1,
        status: ServerHealthStatus.ok,
        checks: const {'socket': true},
        serverTimeUtc: DateTime.utc(2026),
        uptimeSeconds: 100,
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
    });

    test('sessionResponse', () {
      final msg = createSessionResponseMessage(
        requestId: 1,
        clientId: 'c1',
        isAuthenticated: true,
        host: 'h',
        port: 1,
        connectedAt: DateTime.utc(2026),
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
    });

    test('preflightResponse', () {
      final msg = createPreflightResponseMessage(
        requestId: 1,
        status: PreflightStatus.passed,
        checks: const [],
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
    });

    test('executionStatusResponse', () {
      final msg = createExecutionStatusResponseMessage(
        requestId: 1,
        runId: 'r1',
        state: ExecutionState.running,
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
    });

    test('executionQueueResponse', () {
      final msg = createExecutionQueueResponseMessage(
        requestId: 1,
        queue: const [],
        maxQueueSize: 50,
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
    });

    test('metricsResponse', () {
      final msg = createMetricsResponseMessage(
        requestId: 1,
        payload: const <String, dynamic>{
          'totalBackups': 10,
        },
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
      // Campos do payload original preservados
      expect(msg.payload['totalBackups'], 10);
    });
  });

  group('error vs success: contraste', () {
    test('createErrorMessage emite success implicito (ausente)', () {
      final msg = createErrorMessage(
        requestId: 1,
        errorMessage: 'falha',
      );
      // success nao e emitido em error — type = MessageType.error e
      // self-evidente. Cliente faz `getSuccessFromMessage(msg) ?? !isError`.
      expect(msg.payload.containsKey('success'), isFalse);
      expect(msg.header.type, MessageType.error);
      expect(msg.payload['statusCode'], isNotNull);
    });

    test('response com envelope tem success: true', () {
      final msg = createHealthResponseMessage(
        requestId: 1,
        status: ServerHealthStatus.unhealthy,
        checks: const {'socket': true, 'database': false},
        serverTimeUtc: DateTime.utc(2026),
        uptimeSeconds: 100,
        message: 'database down',
      );
      // status pode ser unhealthy mas a RESPOSTA e bem-sucedida
      // (cliente recebeu um snapshot valido). success: true diferencia
      // "request foi processada" de "domain status e ok".
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], 200);
      expect(msg.payload['status'], 'unhealthy');
    });
  });
}
