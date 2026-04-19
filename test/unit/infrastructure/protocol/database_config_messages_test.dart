import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteDatabaseType', () {
    test('fromWire reconhece wire names oficiais', () {
      expect(RemoteDatabaseType.fromWire('sybase'), RemoteDatabaseType.sybase);
      expect(
        RemoteDatabaseType.fromWire('sqlServer'),
        RemoteDatabaseType.sqlServer,
      );
      expect(
        RemoteDatabaseType.fromWire('postgres'),
        RemoteDatabaseType.postgres,
      );
    });

    test('fromWire retorna null para desconhecido/null/vazio', () {
      expect(RemoteDatabaseType.fromWire(null), isNull);
      expect(RemoteDatabaseType.fromWire(''), isNull);
      expect(RemoteDatabaseType.fromWire('mysql'), isNull);
    });
  });

  group('createTestDatabaseConnectionRequest', () {
    test('por id: payload contem databaseType + databaseConfigId', () {
      final msg = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.sybase,
        databaseConfigId: 'cfg-1',
        requestId: 7,
      );
      expect(msg.header.type, MessageType.testDatabaseConnectionRequest);
      expect(msg.header.requestId, 7);
      expect(msg.payload['databaseType'], 'sybase');
      expect(msg.payload['databaseConfigId'], 'cfg-1');
      expect(msg.payload.containsKey('config'), isFalse);
    });

    test('ad-hoc: payload contem databaseType + config map', () {
      final msg = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.postgres,
        config: const {'host': 'h', 'port': 5432},
      );
      expect(msg.payload['databaseType'], 'postgres');
      expect(msg.payload['config'], const {'host': 'h', 'port': 5432});
      expect(msg.payload.containsKey('databaseConfigId'), isFalse);
    });

    test('inclui timeoutMs quando informado', () {
      final msg = createTestDatabaseConnectionRequest(
        databaseType: RemoteDatabaseType.sybase,
        databaseConfigId: 'x',
        timeoutMs: 8000,
      );
      expect(msg.payload['timeoutMs'], 8000);
    });

    test('rejeita ausencia de id e config', () {
      expect(
        () => createTestDatabaseConnectionRequest(
          databaseType: RemoteDatabaseType.sybase,
        ),
        throwsArgumentError,
      );
    });

    test('rejeita id e config simultaneos (XOR)', () {
      expect(
        () => createTestDatabaseConnectionRequest(
          databaseType: RemoteDatabaseType.sybase,
          databaseConfigId: 'x',
          config: const {'a': 1},
        ),
        throwsArgumentError,
      );
    });
  });

  group('createTestDatabaseConnectionResponse', () {
    test('sucesso: success=true + statusCode=200 + connected=true', () {
      final msg = createTestDatabaseConnectionResponse(
        requestId: 1,
        connected: true,
        latencyMs: 50,
        serverTimeUtc: DateTime.utc(2026),
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], StatusCodes.ok);
      expect(msg.payload['connected'], isTrue);
      expect(msg.payload['latencyMs'], 50);
      expect(msg.payload.containsKey('errorCode'), isFalse);
    });

    test('falha com auth: statusCode mapeado de errorCode (401)', () {
      final msg = createTestDatabaseConnectionResponse(
        requestId: 1,
        connected: false,
        latencyMs: 10,
        serverTimeUtc: DateTime.utc(2026),
        error: 'cred invalida',
        errorCode: ErrorCode.authenticationFailed,
      );
      expect(msg.payload['success'], isTrue);
      expect(msg.payload['statusCode'], StatusCodes.unauthorized);
      expect(msg.payload['connected'], isFalse);
      expect(msg.payload['errorCode'], 'AUTH_FAILED');
      expect(msg.payload['error'], 'cred invalida');
    });

    test(
      'falha sem errorCode: statusCode default 503 (banco indisponivel)',
      () {
        final msg = createTestDatabaseConnectionResponse(
          requestId: 1,
          connected: false,
          latencyMs: 5,
          serverTimeUtc: DateTime.utc(2026),
        );
        expect(msg.payload['statusCode'], StatusCodes.serviceUnavailable);
        expect(msg.payload['connected'], isFalse);
      },
    );

    test('inclui details quando informado e nao-vazio', () {
      final msg = createTestDatabaseConnectionResponse(
        requestId: 1,
        connected: true,
        latencyMs: 10,
        serverTimeUtc: DateTime.utc(2026),
        details: const {'version': '14.2'},
      );
      expect(msg.payload['details'], const {'version': '14.2'});
    });

    test('omite details quando vazio (economia de payload)', () {
      final msg = createTestDatabaseConnectionResponse(
        requestId: 1,
        connected: true,
        latencyMs: 10,
        serverTimeUtc: DateTime.utc(2026),
        details: const {},
      );
      expect(msg.payload.containsKey('details'), isFalse);
    });
  });

  group('readTestDatabaseConnectionResponse', () {
    test('parsing completo round-trip', () {
      final created = createTestDatabaseConnectionResponse(
        requestId: 1,
        connected: false,
        latencyMs: 99,
        serverTimeUtc: DateTime.utc(2026, 1, 2, 3, 4, 5),
        error: 'err',
        errorCode: ErrorCode.timeout,
        details: const {'k': 'v'},
      );
      final parsed = readTestDatabaseConnectionResponse(created);
      expect(parsed.connected, isFalse);
      expect(parsed.latencyMs, 99);
      expect(parsed.error, 'err');
      expect(parsed.errorCode, ErrorCode.timeout);
      expect(parsed.details, const {'k': 'v'});
      expect(parsed.serverTimeUtc.toUtc(), DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(parsed.isFailure, isTrue);
      expect(parsed.isSuccess, isFalse);
    });

    test('payload v1 (sem alguns campos): defaults seguros', () {
      // Simula resposta de servidor antigo que so emite connected.
      // Cliente nao pode crashar.
      final partial = createTestDatabaseConnectionResponse(
        requestId: 1,
        connected: true,
        latencyMs: 0,
        serverTimeUtc: DateTime.utc(1970),
      );
      partial.payload.remove('serverTimeUtc');
      partial.payload.remove('latencyMs');
      final parsed = readTestDatabaseConnectionResponse(partial);
      expect(parsed.connected, isTrue);
      expect(parsed.latencyMs, 0);
      expect(parsed.serverTimeUtc.year, 1970);
    });
  });
}
