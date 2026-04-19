import 'dart:io';

import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockServerConnectionRepository extends Mock
    implements IServerConnectionRepository {}

class _MockConnectionLogRepository extends Mock
    implements IConnectionLogRepository {}

int _nextPort = 31000;
int _getPort() {
  final p = _nextPort;
  _nextPort++;
  return p;
}

void main() {
  setUpAll(() {
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
  });

  late _MockServerConnectionRepository repo;
  late _MockConnectionLogRepository logRepo;
  late ConnectionManager manager;
  late TcpSocketServer server;
  late ServerConnectionProvider provider;

  setUp(() {
    repo = _MockServerConnectionRepository();
    logRepo = _MockConnectionLogRepository();
    manager = ConnectionManager();
    server = TcpSocketServer();

    when(() => repo.getAll())
        .thenAnswer((_) async => const rd.Success(<ServerConnection>[]));
    when(
      () => logRepo.insertAttempt(
        clientHost: any(named: 'clientHost'),
        success: any(named: 'success'),
        serverId: any(named: 'serverId'),
        errorMessage: any(named: 'errorMessage'),
        clientId: any(named: 'clientId'),
      ),
    ).thenAnswer((_) async => const rd.Success(rd.unit));

    provider = ServerConnectionProvider(repo, manager, logRepo);
  });

  tearDown(() async {
    provider.dispose();
    await manager.disconnect();
    await server.stop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  group('ServerConnectionProvider — capabilities passa-through (M4.1)', () {
    test('serverCapabilities is null when disconnected', () {
      expect(provider.isConnected, isFalse);
      expect(provider.serverCapabilities, isNull);
      // Getters de feature caem em legacyDefault
      expect(
        provider.isRunIdSupported,
        ServerCapabilities.legacyDefault.supportsRunId,
      );
      expect(provider.isChunkAckSupported, isFalse);
    });

    test('serverCapabilities populated after connect (auto-refresh)', () async {
      final port = _getPort();
      await server.start(port: port);
      await manager.connect(host: '127.0.0.1', port: port);

      // ConnectionManager.connect() ja faz auto-refresh de capabilities
      expect(provider.serverCapabilities, isNotNull);
      // Servidor atual responde com supportsRunId=true (M2.3)
      expect(provider.isRunIdSupported, isTrue);
      expect(provider.isChunkAckSupported, isFalse, reason: 'ADR-002');
    });

    test('disconnect invalidates capabilities cache', () async {
      final port = _getPort();
      await server.start(port: port);
      await manager.connect(host: '127.0.0.1', port: port);
      expect(provider.serverCapabilities, isNotNull);

      await provider.disconnect();
      expect(provider.serverCapabilities, isNull);
      expect(provider.isRunIdSupported, isFalse, reason: 'volta a legacyDefault');
    });
  });

  group('ServerConnectionProvider — refreshServerStatus (M1.10)', () {
    test('serverHealth e serverSession sao null antes do refresh', () {
      expect(provider.serverHealth, isNull);
      expect(provider.serverSession, isNull);
      expect(provider.isServerHealthy, isFalse);
    });

    test(
      'refreshServerStatus quando desconectado limpa cache e nao throws',
      () async {
        await provider.refreshServerStatus();
        expect(provider.serverHealth, isNull);
        expect(provider.serverSession, isNull);
        expect(provider.isRefreshingStatus, isFalse);
      },
    );

    test(
      'refreshServerStatus apos connect popula health + session',
      () async {
        final port = _getPort();
        await server.start(port: port);
        await manager.connect(host: '127.0.0.1', port: port);

        await provider.refreshServerStatus();

        expect(provider.serverHealth, isNotNull);
        expect(provider.serverHealth!.isOk, isTrue);
        expect(provider.isServerHealthy, isTrue);
        expect(provider.serverSession, isNotNull);
        expect(provider.serverSession!.clientId, isNotEmpty);
      },
    );

    test(
      'isRefreshingStatus alterna durante refresh e dispara notifyListeners',
      () async {
        final port = _getPort();
        await server.start(port: port);
        await manager.connect(host: '127.0.0.1', port: port);

        var notifyCount = 0;
        provider.addListener(() => notifyCount++);

        await provider.refreshServerStatus();

        // Pelo menos 2 notificacoes: inicio (loading) e fim (resultado)
        expect(notifyCount, greaterThanOrEqualTo(2));
        expect(provider.isRefreshingStatus, isFalse);
      },
    );

    test(
      'chamadas concorrentes de refreshServerStatus sao idempotentes',
      () async {
        final port = _getPort();
        await server.start(port: port);
        await manager.connect(host: '127.0.0.1', port: port);

        // Dispara 3 em paralelo — apenas a primeira deve realmente
        // executar; as outras retornam imediato
        final futures = [
          provider.refreshServerStatus(),
          provider.refreshServerStatus(),
          provider.refreshServerStatus(),
        ];
        await Future.wait(futures);

        // Estado final consistente, sem flag travada
        expect(provider.isRefreshingStatus, isFalse);
        expect(provider.serverHealth, isNotNull);
      },
    );
  });

  group('ServerConnectionProvider — invalidacao em disconnect', () {
    test(
      'disconnect explicito limpa health + session local',
      () async {
        final port = _getPort();
        await server.start(port: port);
        await manager.connect(host: '127.0.0.1', port: port);
        await provider.refreshServerStatus();

        expect(provider.serverHealth, isNotNull);
        expect(provider.serverSession, isNotNull);

        await provider.disconnect();

        expect(provider.serverHealth, isNull);
        expect(provider.serverSession, isNull);
        expect(provider.isServerHealthy, isFalse);
      },
    );
  });
}
