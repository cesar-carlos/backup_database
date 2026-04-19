import 'dart:io';

import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_connection_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/protocol_versions.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:backup_database/infrastructure/socket/server/execution_status_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
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

  setUpAll(() {
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
  });

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

    test(
      'getSavedConnections when dao provided returns dao.getAll()',
      () async {
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
      },
    );

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
      final mgr = ConnectionManager(
        serverConnectionDao: db.serverConnectionDao,
      );
      addTearDown(mgr.disconnect);
      await mgr.connectToSavedConnection('saved-1');
      expect(mgr.isConnected, isTrue);
      expect(mgr.activeHost, '127.0.0.1');
      expect(mgr.activePort, port);
    });
  });

  group('ConnectionManager capabilities cache (M4.1)', () {
    test(
      'serverCapabilities is null when auto-refresh disabled and no manual call',
      () async {
        final port = getPort();
        await server.start(port: port);
        // Desabilita auto-refresh para testar comportamento bruto do cache
        await manager.connect(
          host: '127.0.0.1',
          port: port,
          refreshCapabilitiesOnConnect: false,
        );

        expect(manager.serverCapabilities, isNull);
      },
    );

    test(
      'getServerCapabilities returns Success with current versions but does '
      'NOT populate cache (use refreshServerCapabilities for that)',
      () async {
        final port = getPort();
        await server.start(port: port);
        // Desabilita auto-refresh para isolar comportamento do
        // getServerCapabilities sem o lado-efeito do connect.
        await manager.connect(
          host: '127.0.0.1',
          port: port,
          refreshCapabilitiesOnConnect: false,
        );

        final result = await manager.getServerCapabilities();
        final caps = result.getOrNull();
        expect(caps, isNotNull);
        expect(caps!.protocolVersion, kCurrentProtocolVersion);
        expect(caps.wireVersion, kCurrentWireVersion);
        expect(caps.supportsRunId, isTrue, reason: 'M2.3 ja entregue');

        // Variante getServerCapabilities() nao toca no cache.
        expect(manager.serverCapabilities, isNull);
      },
    );

    test(
      'refreshServerCapabilities populates cache and returns the snapshot',
      () async {
        final port = getPort();
        await server.start(port: port);
        await manager.connect(
          host: '127.0.0.1',
          port: port,
          refreshCapabilitiesOnConnect: false,
        );

        // Pre-condicao: cache vazio porque auto-refresh esta desligado
        expect(manager.serverCapabilities, isNull);

        final result = await manager.refreshServerCapabilities();
        final caps = result.getOrNull();
        expect(caps, isNotNull);

        // Cache populado e identico ao retorno
        expect(manager.serverCapabilities, isNotNull);
        expect(manager.serverCapabilities!.protocolVersion, caps!.protocolVersion);
        expect(manager.serverCapabilities!.supportsRunId, caps.supportsRunId);
        expect(manager.serverCapabilities!.supportsResume, caps.supportsResume);
      },
    );

    test('disconnect invalidates capabilities cache', () async {
      final port = getPort();
      await server.start(port: port);
      // Connect com auto-refresh ja popula o cache
      await manager.connect(host: '127.0.0.1', port: port);
      expect(manager.serverCapabilities, isNotNull);

      await manager.disconnect();
      expect(manager.serverCapabilities, isNull);
    });

    test(
      'reconnecting with auto-refresh disabled keeps cache null until '
      'refreshServerCapabilities is called',
      () async {
        final port = getPort();
        await server.start(port: port);
        await manager.connect(
          host: '127.0.0.1',
          port: port,
          refreshCapabilitiesOnConnect: false,
        );
        await manager.refreshServerCapabilities();
        final firstSnapshot = manager.serverCapabilities;
        expect(firstSnapshot, isNotNull);

        await manager.disconnect();
        expect(manager.serverCapabilities, isNull);

        await manager.connect(
          host: '127.0.0.1',
          port: port,
          refreshCapabilitiesOnConnect: false,
        );
        // Auto-refresh desligado: cache esta vazio ate refresh explicito
        expect(manager.serverCapabilities, isNull);

        await manager.refreshServerCapabilities();
        expect(manager.serverCapabilities, isNotNull);
      },
    );

    test(
      'refreshServerCapabilities never returns Failure even when call '
      'errors out — uses legacyDefault as graceful fallback',
      () async {
        // Cliente nao conectado: getServerCapabilities() falha,
        // refreshServerCapabilities() deve cair no fallback legacy.
        expect(manager.isConnected, isFalse);

        final result = await manager.refreshServerCapabilities();
        // Sucesso garantido (fallback)
        expect(result.isSuccess(), isTrue);
        final caps = result.getOrNull()!;
        expect(caps.protocolVersion, ServerCapabilities.legacyDefault.protocolVersion);
        expect(caps.supportsRunId, ServerCapabilities.legacyDefault.supportsRunId);
        expect(caps.supportsResume, ServerCapabilities.legacyDefault.supportsResume);
        // Cache populado com legacyDefault
        expect(manager.serverCapabilities, isNotNull);
      },
    );
  });

  group('ConnectionManager auto-refresh & feature getters (M4.1)', () {
    test(
      'connect populates serverCapabilities cache automatically by default',
      () async {
        final port = getPort();
        await server.start(port: port);

        // Antes do connect, cache esta vazio
        expect(manager.serverCapabilities, isNull);

        await manager.connect(host: '127.0.0.1', port: port);

        // Apos connect, cache ja deve estar populado sem chamar
        // refreshServerCapabilities() manualmente
        expect(manager.serverCapabilities, isNotNull);
        expect(
          manager.serverCapabilities!.protocolVersion,
          kCurrentProtocolVersion,
        );
      },
    );

    test(
      'connect with refreshCapabilitiesOnConnect=false leaves cache empty',
      () async {
        final port = getPort();
        await server.start(port: port);

        await manager.connect(
          host: '127.0.0.1',
          port: port,
          refreshCapabilitiesOnConnect: false,
        );

        expect(manager.isConnected, isTrue);
        expect(manager.serverCapabilities, isNull);
      },
    );

    test(
      'feature getters fall back to legacyDefault when cache is null',
      () {
        // Cliente nunca conectado, cache vazio
        expect(manager.serverCapabilities, isNull);

        // Getters devem retornar valores de legacyDefault sem crash
        expect(
          manager.isRunIdSupported,
          ServerCapabilities.legacyDefault.supportsRunId,
        );
        expect(
          manager.isExecutionQueueSupported,
          ServerCapabilities.legacyDefault.supportsExecutionQueue,
        );
        expect(
          manager.isArtifactRetentionSupported,
          ServerCapabilities.legacyDefault.supportsArtifactRetention,
        );
        expect(
          manager.isChunkAckSupported,
          ServerCapabilities.legacyDefault.supportsChunkAck,
        );
      },
    );

    test(
      'feature getters reflect cached capabilities after connect',
      () async {
        final port = getPort();
        await server.start(port: port);
        await manager.connect(host: '127.0.0.1', port: port);

        // Servidor atual: supportsRunId=true (M2.3), demais conforme
        // CapabilitiesMessageHandler.
        expect(manager.isRunIdSupported, isTrue);
        expect(manager.isChunkAckSupported, isFalse, reason: 'ADR-002');
        expect(manager.isExecutionQueueSupported, isFalse, reason: 'pendente PR-3b');
        expect(manager.isArtifactRetentionSupported, isFalse, reason: 'pendente PR-4');
      },
    );

    test(
      'feature getters revertem para legacyDefault apos disconnect',
      () async {
        final port = getPort();
        await server.start(port: port);
        await manager.connect(host: '127.0.0.1', port: port);

        // Sanity check: getters refletem servidor atual
        expect(manager.isRunIdSupported, isTrue);

        await manager.disconnect();

        // Cache invalidado, getters caem no legacyDefault (supportsRunId=false)
        expect(manager.serverCapabilities, isNull);
        expect(
          manager.isRunIdSupported,
          ServerCapabilities.legacyDefault.supportsRunId,
        );
      },
    );
  });

  group('ConnectionManager getServerHealth (M1.10)', () {
    test('retorna ok com checks minimos quando servidor saudavel', () async {
      final port = getPort();
      await server.start(port: port);
      await manager.connect(host: '127.0.0.1', port: port);

      final result = await manager.getServerHealth();
      final health = result.getOrNull();
      expect(health, isNotNull);
      expect(health!.status, ServerHealthStatus.ok);
      expect(health.isOk, isTrue);
      expect(health.isUnhealthy, isFalse);
      // Servidor default reporta socket=true
      expect(health.checks['socket'], isTrue);
      // Uptime sempre >= 0
      expect(health.uptimeSeconds, greaterThanOrEqualTo(0));
    });

    test('falha quando nao conectado', () async {
      expect(manager.isConnected, isFalse);

      final result = await manager.getServerHealth();
      expect(result.isError(), isTrue);
    });
  });

  group('ConnectionManager getServerSession (M1.10)', () {
    test('retorna sessao com clientId atribuido pelo servidor', () async {
      final port = getPort();
      await server.start(port: port);
      await manager.connect(host: '127.0.0.1', port: port);

      final result = await manager.getServerSession();
      final session = result.getOrNull();
      expect(session, isNotNull);
      // Sem auth no test, isAuthenticated=true porque
      // ClientHandler.start() seta como true quando _authentication==null
      expect(session!.isAuthenticated, isTrue);
      // Servidor atribui UUID v4 — confere que e nao-vazio
      expect(session.clientId, isNotEmpty);
      expect(session.host, '127.0.0.1');
      expect(session.port, greaterThan(0));
      // serverId nao foi declarado (sem auth) -> null
      expect(session.serverId, isNull);
    });

    test('falha quando nao conectado', () async {
      expect(manager.isConnected, isFalse);

      final result = await manager.getServerSession();
      expect(result.isError(), isTrue);
    });
  });

  group('ConnectionManager validateServerBackupPrerequisites (F1.8)', () {
    test(
      'retorna passed quando servidor tem mapa de checks vazio (default)',
      () async {
        final port = getPort();
        await server.start(port: port);
        await manager.connect(host: '127.0.0.1', port: port);

        final result = await manager.validateServerBackupPrerequisites();
        final preflight = result.getOrNull();
        expect(preflight, isNotNull);
        // PreflightMessageHandler default vem com mapa de checks vazio
        // (wirings em producao adicionam checks reais).
        expect(preflight!.isOk, isTrue);
        expect(preflight.isBlocked, isFalse);
        expect(preflight.checks, isEmpty);
        expect(preflight.serverTimeUtc.isUtc, isTrue);
      },
    );

    test('falha quando nao conectado', () async {
      expect(manager.isConnected, isFalse);

      final result = await manager.validateServerBackupPrerequisites();
      expect(result.isError(), isTrue);
    });
  });

  group('ConnectionManager getExecutionStatus (PR-2 base / M2.3)', () {
    test('retorna notFound para runId desconhecido (registry vazio)', () async {
      // Setup: TcpSocketServer customizado com handler + registry novos
      final registry = RemoteExecutionRegistry();
      final customServer = TcpSocketServer(
        executionStatusHandler: ExecutionStatusMessageHandler(
          executionRegistry: registry,
        ),
      );
      final port = getPort();
      await customServer.start(port: port);
      addTearDown(() async {
        await customServer.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      await manager.connect(host: '127.0.0.1', port: port);

      final result = await manager.getExecutionStatus('never-registered');
      final status = result.getOrNull();
      expect(status, isNotNull);
      expect(status!.state, ExecutionState.notFound);
      expect(status.isNotFound, isTrue);
      expect(status.runId, 'never-registered');
    });

    test('retorna running quando registry tem entrada ativa', () async {
      final registry = RemoteExecutionRegistry();
      final runId = registry.generateRunId('sched-prod');
      registry.register(
        runId: runId,
        scheduleId: 'sched-prod',
        clientId: 'client-A',
        requestId: 1,
        sendToClient: (clientId, msg) async {},
      );

      final customServer = TcpSocketServer(
        executionStatusHandler: ExecutionStatusMessageHandler(
          executionRegistry: registry,
        ),
      );
      final port = getPort();
      await customServer.start(port: port);
      addTearDown(() async {
        await customServer.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      await manager.connect(host: '127.0.0.1', port: port);

      final result = await manager.getExecutionStatus(runId);
      final status = result.getOrNull();
      expect(status, isNotNull);
      expect(status!.state, ExecutionState.running);
      expect(status.isActive, isTrue);
      expect(status.scheduleId, 'sched-prod');
      expect(status.clientId, 'client-A');
    });

    test('falha quando runId vazio (validacao client-side)', () async {
      final result = await manager.getExecutionStatus('');
      expect(result.isError(), isTrue);
    });

    test('falha quando nao conectado', () async {
      expect(manager.isConnected, isFalse);

      final result = await manager.getExecutionStatus('any-runid');
      expect(result.isError(), isTrue);
    });
  });
}
