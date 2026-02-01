import 'package:backup_database/infrastructure/datasources/daos/server_connection_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

int _nextPort = 29700;

int getPort() {
  final p = _nextPort;
  _nextPort++;
  return p;
}

class MockServerConnectionDao extends Mock implements ServerConnectionDao {}

void main() {
  late ConnectionManager manager;
  late TcpSocketServer server;

  setUp(() {
    manager = ConnectionManager();
    server = TcpSocketServer();
  });

  tearDown(() async {
    await manager.disconnect();
    await server.stop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  group('ConnectionManager', () {
    test('should not be connected when created', () {
      expect(manager.isConnected, isFalse);
      expect(manager.status, ConnectionStatus.disconnected);
      expect(manager.activeClient, isNull);
      expect(manager.activeHost, isNull);
      expect(manager.activePort, isNull);
    });

    test('disconnect when not connected should not throw', () async {
      await manager.disconnect();
    });

    test('connect then disconnect should work', () async {
      final port = getPort();
      await server.start(port: port);

      await manager.connect(host: '127.0.0.1', port: port);
      expect(manager.isConnected, isTrue);
      expect(manager.status, ConnectionStatus.connected);
      expect(manager.activeHost, '127.0.0.1');
      expect(manager.activePort, port);
      expect(manager.activeClient, isNotNull);

      await manager.disconnect();
      expect(manager.isConnected, isFalse);
      expect(manager.status, ConnectionStatus.disconnected);
      expect(manager.activeHost, isNull);
      expect(manager.activePort, isNull);
      expect(manager.activeClient, isNull);
    });

    test('send when connected should deliver message to server', () async {
      final port = getPort();
      await server.start(port: port);
      await manager.connect(host: '127.0.0.1', port: port);

      Message? received;
      server.messageStream.listen((m) {
        received = m;
      });

      final msg = Message(
        header: MessageHeader(type: MessageType.metricsRequest, length: 2),
        payload: <String, dynamic>{'q': 1},
        checksum: 0,
      );
      await manager.send(msg);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received, isNotNull);
      expect(received!.header.type, MessageType.metricsRequest);
    });

    test('send when not connected should throw', () async {
      final msg = Message(
        header: MessageHeader(type: MessageType.heartbeat, length: 0),
        payload: <String, dynamic>{},
        checksum: 0,
      );
      expect(
        () => manager.send(msg),
        throwsA(isA<StateError>()),
      );
    });

    test('getSavedConnections when no dao returns empty list', () async {
      final mgr = ConnectionManager();
      addTearDown(mgr.disconnect);
      final list = await mgr.getSavedConnections();
      expect(list, isEmpty);
    });

    test('getSavedConnections when dao provided returns dao.getAll()', () async {
      final mockDao = MockServerConnectionDao();
      final now = DateTime.now();
      final saved = [
        ServerConnectionsTableData(
          id: 'conn-1',
          name: 'Server A',
          serverId: 's1',
          host: '127.0.0.1',
          port: 9527,
          password: 'p1',
          isOnline: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];
      when(mockDao.getAll).thenAnswer((_) async => saved);
      final mgr = ConnectionManager(serverConnectionDao: mockDao);
      addTearDown(mgr.disconnect);
      final list = await mgr.getSavedConnections();
      expect(list.length, 1);
      expect(list.first.id, 'conn-1');
      expect(list.first.name, 'Server A');
      expect(list.first.host, '127.0.0.1');
      verify(mockDao.getAll).called(1);
    });

    test('connectToSavedConnection when no dao throws', () async {
      final mgr = ConnectionManager();
      addTearDown(mgr.disconnect);
      expect(
        () => mgr.connectToSavedConnection('any-id'),
        throwsA(isA<StateError>()),
      );
    });

    test('connectToSavedConnection when connection not found throws', () async {
      final mockDao = MockServerConnectionDao();
      when(() => mockDao.getById(any())).thenAnswer((_) async => null);
      final mgr = ConnectionManager(serverConnectionDao: mockDao);
      addTearDown(mgr.disconnect);
      expect(
        () => mgr.connectToSavedConnection('missing-id'),
        throwsA(isA<StateError>()),
      );
      verify(() => mockDao.getById('missing-id')).called(1);
    });

    test('connectToSavedConnection with valid id connects', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final port = getPort();
      await server.start(port: port);
      addTearDown(() async {
        await server.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      final now = DateTime.now();
      await db.serverConnectionDao.insertConnection(
        ServerConnectionsTableCompanion.insert(
          id: 'saved-1',
          name: 'Local',
          serverId: '',
          host: '127.0.0.1',
          port: Value(port),
          password: '',
          isOnline: const Value(false),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final mgr = ConnectionManager(serverConnectionDao: db.serverConnectionDao);
      addTearDown(mgr.disconnect);
      await mgr.connectToSavedConnection('saved-1');
      expect(mgr.isConnected, isTrue);
      expect(mgr.activeHost, '127.0.0.1');
      expect(mgr.activePort, port);
    });
  });
}
