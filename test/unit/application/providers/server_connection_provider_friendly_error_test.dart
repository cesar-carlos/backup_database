import 'dart:io';

import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/domain/repositories/i_connection_log_repository.dart';
import 'package:backup_database/domain/repositories/i_server_connection_repository.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockConnectionManager extends Mock implements ConnectionManager {}

class _MockServerConnectionRepository extends Mock
    implements IServerConnectionRepository {}

class _MockConnectionLogRepository extends Mock
    implements IConnectionLogRepository {}

void main() {
  setUpAll(() {
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
  });

  late _MockConnectionManager manager;
  late _MockServerConnectionRepository repo;
  late _MockConnectionLogRepository logRepo;
  late ServerConnectionProvider provider;

  setUp(() {
    manager = _MockConnectionManager();
    repo = _MockServerConnectionRepository();
    logRepo = _MockConnectionLogRepository();

    // Defaults to avoid mocktail complaining about uncovered methods
    // called by the provider constructor (loadConnections,
    // _listenToConnectionStatus).
    when(
      () => repo.getAll(),
    ).thenAnswer((_) async => const rd.Success(<ServerConnection>[]));
    when(() => manager.statusStream).thenReturn(null);
    when(() => manager.isConnected).thenReturn(false);
  });

  ServerConnectionProvider buildProvider() {
    return ServerConnectionProvider(repo, manager, logRepo);
  }

  group(
    'friendlyConnectionErrorMessage — §audit-2026-05-28 wave 2 P1',
    () {
      test('falls back to lastErrorMessage when no errorCode set', () {
        when(() => manager.lastErrorCode).thenReturn(null);
        when(
          () => manager.lastErrorMessage,
        ).thenReturn('Erro genérico do servidor');

        provider = buildProvider();

        expect(
          provider.friendlyConnectionErrorMessage,
          'Erro genérico do servidor',
        );
      });

      test('maps licenseDenied to an actionable message', () {
        when(() => manager.lastErrorCode).thenReturn(ErrorCode.licenseDenied);
        when(
          () => manager.lastErrorMessage,
        ).thenReturn('LICENSE_DENIED: foo bar internal detail');

        provider = buildProvider();

        final msg = provider.friendlyConnectionErrorMessage;
        expect(msg, isNotNull);
        expect(msg, contains('licença'));
        expect(msg, contains('administrador'));
        // NÃO deve vazar o texto cru do servidor (que pode trazer
        // identificadores internos / detalhes técnicos).
        expect(msg, isNot(contains('foo bar internal detail')));
      });

      test('maps authenticationFailed to senha/identificador message', () {
        when(
          () => manager.lastErrorCode,
        ).thenReturn(ErrorCode.authenticationFailed);
        when(() => manager.lastErrorMessage).thenReturn('AUTH_FAILED');

        provider = buildProvider();

        final msg = provider.friendlyConnectionErrorMessage;
        expect(msg, contains('Falha de autenticação'));
        expect(msg, contains('senha'));
      });

      test('maps timeout/connectionLost to network hint', () {
        for (final code in [
          ErrorCode.timeout,
          ErrorCode.connectionLost,
        ]) {
          when(() => manager.lastErrorCode).thenReturn(code);
          when(() => manager.lastErrorMessage).thenReturn(code.code);

          provider = buildProvider();

          final msg = provider.friendlyConnectionErrorMessage;
          expect(msg, contains('rede'), reason: 'failed for ${code.code}');
        }
      });

      test('maps unsupportedProtocolVersion to update hint', () {
        when(
          () => manager.lastErrorCode,
        ).thenReturn(ErrorCode.unsupportedProtocolVersion);
        when(
          () => manager.lastErrorMessage,
        ).thenReturn('UNSUPPORTED_PROTOCOL_VERSION');

        provider = buildProvider();

        expect(
          provider.friendlyConnectionErrorMessage,
          contains('Atualize o cliente'),
        );
      });

      test('connectionErrorCode getter passes through', () {
        when(() => manager.lastErrorCode).thenReturn(ErrorCode.queueFull);
        when(() => manager.lastErrorMessage).thenReturn('QUEUE_FULL');

        provider = buildProvider();

        expect(provider.connectionErrorCode, ErrorCode.queueFull);
      });
    },
  );
}
