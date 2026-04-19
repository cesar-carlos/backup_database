import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/database_connection_prober.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingProber implements DatabaseConnectionProber {
  RemoteDatabaseType? lastType;
  DatabaseConfigRef? lastRef;
  Duration? lastTimeout;
  DatabaseProbeOutcome Function() outcome = () =>
      DatabaseProbeOutcome.success(latencyMs: 42);

  @override
  Future<DatabaseProbeOutcome> probe({
    required RemoteDatabaseType databaseType,
    required DatabaseConfigRef configRef,
    Duration? timeout,
  }) async {
    lastType = databaseType;
    lastRef = configRef;
    lastTimeout = timeout;
    return outcome();
  }
}

class _ThrowingProber implements DatabaseConnectionProber {
  @override
  Future<DatabaseProbeOutcome> probe({
    required RemoteDatabaseType databaseType,
    required DatabaseConfigRef configRef,
    Duration? timeout,
  }) async {
    throw StateError('boom');
  }
}

void main() {
  late _CapturingProber prober;
  late DatabaseConfigMessageHandler handler;
  late List<Message> sentMessages;

  Future<void> send(String clientId, Message m) async {
    sentMessages.add(m);
  }

  setUp(() {
    prober = _CapturingProber();
    handler = DatabaseConfigMessageHandler(
      prober: prober,
      clock: () => DateTime.utc(2026, 4, 19, 12),
    );
    sentMessages = [];
  });

  group('DatabaseConfigMessageHandler', () {
    test('ignora mensagens de outros tipos (no-op)', () async {
      final unrelated = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: const <String, dynamic>{},
        checksum: 0,
      );
      await handler.handle('c1', unrelated, send);
      expect(sentMessages, isEmpty);
      expect(prober.lastType, isNull);
    });

    test('despacha por id e responde com sucesso', () async {
      final req = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.sybase,
        databaseConfigId: 'cfg-1',
        requestId: 7,
      );
      await handler.handle('c1', req, send);

      expect(prober.lastType, RemoteDatabaseType.sybase);
      expect(prober.lastRef, isA<DatabaseConfigById>());
      expect((prober.lastRef! as DatabaseConfigById).id, 'cfg-1');

      expect(sentMessages, hasLength(1));
      final resp = sentMessages.single;
      expect(resp.header.type, MessageType.testDatabaseConnectionResponse);
      expect(resp.header.requestId, 7);
      expect(resp.payload['connected'], isTrue);
      expect(resp.payload['latencyMs'], 42);
      expect(resp.payload['statusCode'], 200);
      expect(resp.payload['success'], isTrue);
    });

    test('despacha ad-hoc com config map', () async {
      final req = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.postgres,
        config: const {'host': 'h', 'port': 5432},
      );
      await handler.handle('c1', req, send);

      expect(prober.lastRef, isA<DatabaseConfigAdhoc>());
      expect(
        (prober.lastRef! as DatabaseConfigAdhoc).config,
        const {'host': 'h', 'port': 5432},
      );
    });

    test('propaga timeout do payload em ms para o prober', () async {
      final req = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.sybase,
        databaseConfigId: 'x',
        timeoutMs: 8000,
      );
      await handler.handle('c1', req, send);
      expect(prober.lastTimeout, const Duration(milliseconds: 8000));
    });

    test('falha do prober vira response com errorCode e statusCode', () async {
      prober.outcome = () => DatabaseProbeOutcome.failure(
            latencyMs: 10,
            error: 'cred invalida',
            errorCode: ErrorCode.authenticationFailed,
          );
      final req = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.sybase,
        databaseConfigId: 'x',
      );
      await handler.handle('c1', req, send);

      final resp = sentMessages.single;
      expect(resp.payload['connected'], isFalse);
      expect(resp.payload['errorCode'], 'AUTH_FAILED');
      expect(resp.payload['statusCode'], 401);
    });

    test('exception do prober vira erro 500 unknown (fail-closed)', () async {
      handler = DatabaseConfigMessageHandler(
        prober: _ThrowingProber(),
        clock: () => DateTime.utc(2026),
      );
      final req = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.sybase,
        databaseConfigId: 'x',
      );
      await handler.handle('c1', req, send);

      final resp = sentMessages.single;
      expect(resp.header.type, MessageType.testDatabaseConnectionResponse);
      expect(resp.payload['connected'], isFalse);
      expect(resp.payload['errorCode'], 'UNKNOWN');
      expect(resp.payload['statusCode'], 500);
      expect(resp.payload['error'], contains('boom'));
    });

    test('databaseType ausente -> error 400 invalidRequest', () async {
      final req = Message(
        header: MessageHeader(
          type: MessageType.testDatabaseConnectionRequest,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{
          'databaseConfigId': 'x',
        },
        checksum: 0,
      );
      await handler.handle('c1', req, send);
      final resp = sentMessages.single;
      expect(resp.header.type, MessageType.error);
      expect(getErrorCodeFromMessage(resp), ErrorCode.invalidRequest);
    });

    test(
      'databaseType invalido -> error 400 invalidRequest',
      () async {
        final req = Message(
          header: MessageHeader(
            type: MessageType.testDatabaseConnectionRequest,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{
            'databaseType': 'mongo',
            'databaseConfigId': 'x',
          },
          checksum: 0,
        );
        await handler.handle('c1', req, send);
        final resp = sentMessages.single;
        expect(resp.header.type, MessageType.error);
        expect(getErrorCodeFromMessage(resp), ErrorCode.invalidRequest);
      },
    );

    test(
      'XOR violado (id + config simultaneos) -> error 400 invalidRequest',
      () async {
        final req = Message(
          header: MessageHeader(
            type: MessageType.testDatabaseConnectionRequest,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{
            'databaseType': 'sybase',
            'databaseConfigId': 'x',
            'config': <String, dynamic>{'a': 1},
          },
          checksum: 0,
        );
        await handler.handle('c1', req, send);
        final resp = sentMessages.single;
        expect(resp.header.type, MessageType.error);
        expect(getErrorCodeFromMessage(resp), ErrorCode.invalidRequest);
      },
    );

    test('NotConfiguredProber default responde com falha unknown', () async {
      handler = DatabaseConfigMessageHandler(
        clock: () => DateTime.utc(2026),
      );
      final req = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.sybase,
        databaseConfigId: 'x',
      );
      await handler.handle('c1', req, send);
      final resp = sentMessages.single;
      expect(resp.payload['connected'], isFalse);
      expect(resp.payload['errorCode'], 'UNKNOWN');
      expect(resp.payload['error'], contains('nao configurada'));
    });
  });
}
