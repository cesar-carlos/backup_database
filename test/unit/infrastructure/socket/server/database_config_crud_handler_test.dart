import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingStore implements DatabaseConfigStore {
  final List<({String op, RemoteDatabaseType type, Object? arg})> calls = [];
  DatabaseConfigOutcome Function(String op) outcome = (op) =>
      DatabaseConfigOutcome.success(
        config: <String, dynamic>{'id': 'cfg-x', 'name': 'X'},
      );

  @override
  Future<DatabaseConfigOutcome> list(RemoteDatabaseType type) async {
    calls.add((op: 'list', type: type, arg: null));
    final o = outcome('list');
    if (o.success && o.configs == null) {
      return DatabaseConfigOutcome.success(
        configs: const [
          {'id': 'a'},
          {'id': 'b'},
        ],
      );
    }
    return o;
  }

  @override
  Future<DatabaseConfigOutcome> create(
    RemoteDatabaseType type,
    Map<String, dynamic> config,
  ) async {
    calls.add((op: 'create', type: type, arg: config));
    return outcome('create');
  }

  @override
  Future<DatabaseConfigOutcome> update(
    RemoteDatabaseType type,
    Map<String, dynamic> config,
  ) async {
    calls.add((op: 'update', type: type, arg: config));
    return outcome('update');
  }

  @override
  Future<DatabaseConfigOutcome> delete(
    RemoteDatabaseType type,
    String configId,
  ) async {
    calls.add((op: 'delete', type: type, arg: configId));
    return outcome('delete');
  }
}

void main() {
  late _RecordingStore store;
  late DatabaseConfigMessageHandler handler;
  late List<Message> sent;

  Future<void> sendToClient(String _, Message m) async {
    sent.add(m);
  }

  setUp(() {
    store = _RecordingStore();
    handler = DatabaseConfigMessageHandler(
      store: store,
      clock: () => DateTime.utc(2026, 4, 19, 12),
    );
    sent = [];
  });

  group('listDatabaseConfigs', () {
    test('responde com lista do store', () async {
      final req = createListDatabaseConfigsRequest(
        databaseType: RemoteDatabaseType.sybase,
      );
      await handler.handle('c1', req, sendToClient);

      final resp = sent.single;
      expect(resp.header.type, MessageType.listDatabaseConfigsResponse);
      expect(resp.payload['databaseType'], 'sybase');
      expect((resp.payload['configs'] as List), hasLength(2));
      expect(resp.payload['statusCode'], 200);
      expect(resp.payload['success'], isTrue);
    });

    test('databaseType ausente -> 400', () async {
      final bad = Message(
        header: MessageHeader(
          type: MessageType.listDatabaseConfigsRequest,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{},
        checksum: 0,
      );
      await handler.handle('c1', bad, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.invalidRequest);
    });

    test('falha do store vira error', () async {
      store.outcome = (op) => DatabaseConfigOutcome.failure(
            error: 'db down',
            errorCode: ErrorCode.ioError,
          );
      final req = createListDatabaseConfigsRequest(
        databaseType: RemoteDatabaseType.sybase,
      );
      await handler.handle('c1', req, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.ioError);
    });
  });

  group('createDatabaseConfig', () {
    test('chama store.create e responde com operation=created', () async {
      final req = createCreateDatabaseConfigRequest(
        databaseType: RemoteDatabaseType.sybase,
        config: const {'id': 'new-id', 'name': 'Foo'},
      );
      await handler.handle('c1', req, sendToClient);

      expect(store.calls.single.op, 'create');
      final resp = sent.single;
      expect(resp.header.type, MessageType.databaseConfigMutationResponse);
      expect(resp.payload['operation'], 'created');
      expect(resp.payload['databaseType'], 'sybase');
      expect(resp.payload['configId'], 'cfg-x');
    });

    test('payload sem config -> 400', () async {
      final bad = Message(
        header: MessageHeader(
          type: MessageType.createDatabaseConfigRequest,
          length: 0,
          requestId: 1,
        ),
        payload: const <String, dynamic>{
          'databaseType': 'sybase',
        },
        checksum: 0,
      );
      await handler.handle('c1', bad, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.invalidRequest);
    });

    test('idempotencyKey: 2a chamada nao chama store novamente', () async {
      final req = createCreateDatabaseConfigRequest(
        databaseType: RemoteDatabaseType.sybase,
        config: const {'id': 'x', 'name': 'Foo'},
        idempotencyKey: 'idem-create',
      );
      await handler.handle('c1', req, sendToClient);
      await handler.handle('c1', req, sendToClient);

      expect(store.calls, hasLength(1));
      expect(sent, hasLength(2));
      expect(
        sent[0].payload['configId'],
        equals(sent[1].payload['configId']),
      );
    });
  });

  group('updateDatabaseConfig', () {
    test('chama store.update e responde com operation=updated', () async {
      final req = createUpdateDatabaseConfigRequest(
        databaseType: RemoteDatabaseType.postgres,
        config: const {'id': 'cfg-1', 'name': 'Bar'},
      );
      await handler.handle('c1', req, sendToClient);
      expect(store.calls.single.op, 'update');
      final resp = sent.single;
      expect(resp.payload['operation'], 'updated');
      expect(resp.payload['databaseType'], 'postgres');
      expect(resp.payload['configId'], 'cfg-1');
    });

    test('config sem id -> 400', () async {
      final req = createUpdateDatabaseConfigRequest(
        databaseType: RemoteDatabaseType.postgres,
        config: const {'name': 'no-id'},
      );
      await handler.handle('c1', req, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.invalidRequest);
    });
  });

  group('deleteDatabaseConfig', () {
    test('chama store.delete e responde com operation=deleted', () async {
      final req = createDeleteDatabaseConfigRequest(
        databaseType: RemoteDatabaseType.sqlServer,
        configId: 'cfg-99',
      );
      await handler.handle('c1', req, sendToClient);
      expect(store.calls.single.op, 'delete');
      expect(store.calls.single.arg, 'cfg-99');
      final resp = sent.single;
      expect(resp.payload['operation'], 'deleted');
      expect(resp.payload['databaseType'], 'sqlServer');
      expect(resp.payload['configId'], 'cfg-99');
    });

    test('configId vazio -> 400', () async {
      final req = createDeleteDatabaseConfigRequest(
        databaseType: RemoteDatabaseType.sqlServer,
        configId: '',
      );
      await handler.handle('c1', req, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.invalidRequest);
    });
  });

  group('NotConfiguredDatabaseConfigStore default', () {
    test('todas operacoes retornam errorCode=UNKNOWN', () async {
      handler = DatabaseConfigMessageHandler(
        clock: () => DateTime.utc(2026),
      );
      final req = createListDatabaseConfigsRequest(
        databaseType: RemoteDatabaseType.sybase,
      );
      await handler.handle('c1', req, sendToClient);
      expect(getErrorCodeFromMessage(sent.single), ErrorCode.unknown);
      expect(getErrorFromMessage(sent.single), contains('nao configurado'));
    });
  });

  group('Snapshots tipados', () {
    test('readDatabaseConfigListResponse round-trip', () {
      final msg = createListDatabaseConfigsResponse(
        requestId: 1,
        databaseType: RemoteDatabaseType.sqlServer,
        configs: const [
          {'id': 'a'},
          {'id': 'b'},
        ],
        serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
      );
      final parsed = readDatabaseConfigListResponse(msg);
      expect(parsed.databaseType, RemoteDatabaseType.sqlServer);
      expect(parsed.count, 2);
      expect(parsed.isEmpty, isFalse);
    });

    test('readDatabaseConfigMutationResponse round-trip', () {
      final msg = createDatabaseConfigMutationResponse(
        requestId: 1,
        operation: 'updated',
        databaseType: RemoteDatabaseType.postgres,
        configId: 'cfg-2',
        config: const {'id': 'cfg-2', 'name': 'X'},
      );
      final parsed = readDatabaseConfigMutationResponse(msg);
      expect(parsed.operation, 'updated');
      expect(parsed.isUpdated, isTrue);
      expect(parsed.databaseType, RemoteDatabaseType.postgres);
      expect(parsed.configId, 'cfg-2');
      expect(parsed.config?['name'], 'X');
    });
  });
}
