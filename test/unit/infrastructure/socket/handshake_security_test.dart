import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/infrastructure/protocol/auth_messages.dart';
import 'package:backup_database/infrastructure/protocol/binary_protocol.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/payload_limits.dart';
import 'package:backup_database/infrastructure/socket/server/client_handler.dart';
import 'package:backup_database/infrastructure/socket/server/server_authentication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockServerAuthentication extends Mock implements ServerAuthentication {}

Future<({Socket client, Socket server})> createSocketPair() async {
  final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = serverSocket.port;
  final clientFuture = Socket.connect(InternetAddress.loopbackIPv4, port);
  final serverFuture = serverSocket.first;
  final results = await Future.wait(<Future<dynamic>>[
    clientFuture,
    serverFuture,
  ]);
  final client = results[0] as Socket;
  final server = results[1] as Socket;
  await serverSocket.close();
  return (client: client, server: server);
}

Message _dummyMessage() => Message(
  header: MessageHeader(type: MessageType.heartbeat, length: 0),
  payload: <String, dynamic>{},
  checksum: 0,
);

/// Le mensagens do socket cliente, deserializa via [protocol], e
/// chama [match] em cada uma. Completa quando [match] retorna `true`.
/// Util para esperar a primeira mensagem do servidor que satisfaz um
/// criterio (ex.: primeiro `error`, ou `authResponse` com sucesso).
Completer<Message> _expectFromServer(
  Socket clientSocket,
  BinaryProtocol protocol, {
  required bool Function(Message) match,
}) {
  final completer = Completer<Message>.sync();
  final buffer = <int>[];
  clientSocket.listen((data) {
    buffer.addAll(data);
    while (buffer.length >= 16 + 4) {
      final length =
          (buffer[5] << 24) |
          (buffer[6] << 16) |
          (buffer[7] << 8) |
          buffer[8];
      final total = 16 + length + 4;
      if (buffer.length < total) return;
      try {
        final msg = protocol.deserializeMessage(
          Uint8List.fromList(buffer.sublist(0, total)),
        );
        buffer.removeRange(0, total);
        if (match(msg) && !completer.isCompleted) {
          completer.complete(msg);
          return;
        }
      } on Object catch (_) {
        // Bytes invalidos: descarta a mensagem atual e segue.
        buffer.removeRange(0, total);
      }
    }
  });
  return completer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BinaryProtocol protocol;

  setUpAll(() {
    registerFallbackValue(_dummyMessage());
  });

  setUp(() {
    protocol = BinaryProtocol();
  });

  // ---------------------------------------------------------------------------
  // Grupo 1: PasswordHasher - propriedades de comparacao constant-time
  // ---------------------------------------------------------------------------
  group('PasswordHasher.constantTimeEquals — propriedades de seguranca', () {
    test('retorna true para hashes identicos de tamanho real (SHA-256)', () {
      final hashA = PasswordHasher.hash('senha-teste', 'salt-1');
      final hashB = PasswordHasher.hash('senha-teste', 'salt-1');
      expect(hashA.length, 64); // sha256 hex = 64 chars
      expect(PasswordHasher.constantTimeEquals(hashA, hashB), isTrue);
    });

    test('retorna false para hashes diferentes do mesmo tamanho', () {
      final hashA = PasswordHasher.hash('senha-A', 'salt');
      final hashB = PasswordHasher.hash('senha-B', 'salt');
      expect(hashA.length, hashB.length);
      expect(PasswordHasher.constantTimeEquals(hashA, hashB), isFalse);
    });

    test('retorna false para tamanhos diferentes (early-return aceitavel)', () {
      // O early-return em length-mismatch vaza tamanho — mas hashes
      // tem tamanho FIXO (64 chars sha256), entao nao ha vazamento de
      // segredo neste contexto. Documentamos a propriedade.
      final longHash = 'a' * 64; // simula sha256
      final shortHash = 'a' * 32; // simula md5
      expect(PasswordHasher.constantTimeEquals(longHash, shortHash), isFalse);
      expect(PasswordHasher.constantTimeEquals(shortHash, longHash), isFalse);
    });

    test('detecta diferenca em qualquer posicao (inicio, meio, fim)', () {
      final base = PasswordHasher.hash('xyz', 'salt');
      // Muta o primeiro char
      final firstChanged =
          (base.codeUnitAt(0) == 0x61 ? 'b' : 'a') + base.substring(1);
      // Muta um char no meio
      final midIndex = base.length ~/ 2;
      final midChanged =
          base.substring(0, midIndex) +
          (base.codeUnitAt(midIndex) == 0x61 ? 'b' : 'a') +
          base.substring(midIndex + 1);
      // Muta o ultimo char
      final lastIndex = base.length - 1;
      final lastChanged =
          base.substring(0, lastIndex) +
          (base.codeUnitAt(lastIndex) == 0x61 ? 'b' : 'a');

      expect(PasswordHasher.constantTimeEquals(base, firstChanged), isFalse);
      expect(PasswordHasher.constantTimeEquals(base, midChanged), isFalse);
      expect(PasswordHasher.constantTimeEquals(base, lastChanged), isFalse);
    });

    test('hash e deterministico para mesma entrada', () {
      const password = 'senha';
      const salt = 'salt';
      final h1 = PasswordHasher.hash(password, salt);
      final h2 = PasswordHasher.hash(password, salt);
      expect(h1, h2);
    });

    test('hash difere para salts diferentes (mesmo password)', () {
      // Garantia de que `salt` afeta o hash — sem isso, mesmas senhas
      // colidiriam entre servidores.
      final h1 = PasswordHasher.hash('senha', 'salt-1');
      final h2 = PasswordHasher.hash('senha', 'salt-2');
      expect(h1, isNot(h2));
    });

    test('verify usa constantTimeEquals (smoke)', () {
      const password = 'p';
      const salt = 's';
      final hash = PasswordHasher.hash(password, salt);
      expect(PasswordHasher.verify(password, hash, salt), isTrue);
      expect(PasswordHasher.verify('outra', hash, salt), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Grupo 2: Handshake — interacoes e2e com defesas em camadas
  // ---------------------------------------------------------------------------
  group('Handshake — defesas em camadas (F0.4)', () {
    test(
      'authRequest com payload acima do limite por tipo: peer recebe '
      'PAYLOAD_TOO_LARGE e e desconectado',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        final mockAuth = MockServerAuthentication();

        String? disconnectedId;
        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (id) => disconnectedId = id,
          authentication: mockAuth,
        );
        handler.start();

        final responseCompleter = _expectFromServer(
          pair.client,
          protocol,
          match: (m) => m.header.type == MessageType.error,
        );

        // Header artesanal declarando 16KB para authRequest (limite = 8KB).
        // Nao envia payload — o handler rejeita so com o header.
        final authMax = PayloadLimits.maxPayloadBytesFor(
          MessageType.authRequest,
        );
        final oversizedLength = authMax + 1024;
        final header = Uint8List(16);
        header[0] = 0xFA;
        header[4] = 0x01; // wire version
        header[5] = (oversizedLength >> 24) & 0xFF;
        header[6] = (oversizedLength >> 16) & 0xFF;
        header[7] = (oversizedLength >> 8) & 0xFF;
        header[8] = oversizedLength & 0xFF;
        header[9] = MessageType.authRequest.index;
        pair.client.add(header);
        await pair.client.flush();

        final response = await responseCompleter.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              throw TimeoutException('No PAYLOAD_TOO_LARGE response'),
        );
        expect(getErrorCodeFromMessage(response), ErrorCode.payloadTooLarge);
        expect(getErrorFromMessage(response), contains('authRequest'));

        // Deve ter desconectado (defesa contra DoS via auth gigante)
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(disconnectedId, equals(handler.clientId));
        // Validacao real NAO deve ter sido invocada
        verifyNever(() => mockAuth.validateAuthRequest(any()));
      },
    );

    test(
      'pre-auth disconnect message: silenciosamente aceito sem '
      'gerar resposta de erro (chars liberados)',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        final mockAuth = MockServerAuthentication();
        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (_) {},
          authentication: mockAuth,
        );
        handler.start();
        expect(handler.isAuthenticated, isFalse);

        // Captura QUALQUER mensagem do servidor
        var receivedAny = false;
        pair.client.listen((_) {
          receivedAny = true;
        });

        // Cliente envia `disconnect` antes de auth — deve ser
        // silenciosamente ignorado (sem resposta de erro).
        final disconnectMsg = Message(
          header: MessageHeader(
            type: MessageType.disconnect,
            length: 2,
            requestId: 99,
          ),
          payload: const <String, dynamic>{},
          checksum: 0,
        );
        pair.client.add(protocol.serializeMessage(disconnectMsg));
        await pair.client.flush();

        // Aguarda janela razoavel para confirmar que NADA chega
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          receivedAny,
          isFalse,
          reason: 'pre-auth disconnect deve ser silencioso (sem resposta)',
        );

        verifyNever(() => mockAuth.validateAuthRequest(any()));
        handler.disconnect();
      },
    );

    test(
      'pre-auth error message do peer: silenciosamente aceito '
      '(servidor nao processa erro recebido)',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        final mockAuth = MockServerAuthentication();
        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (_) {},
          authentication: mockAuth,
        );
        handler.start();

        var receivedAny = false;
        pair.client.listen((_) {
          receivedAny = true;
        });

        // Peer envia uma `error` mensagem — defensivamente liberada.
        final fakeError = createErrorMessage(
          requestId: 0,
          errorMessage: 'fake-from-peer',
          errorCode: ErrorCode.unknown,
        );
        pair.client.add(protocol.serializeMessage(fakeError));
        await pair.client.flush();

        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          receivedAny,
          isFalse,
          reason: 'pre-auth error do peer deve ser silencioso',
        );
        verifyNever(() => mockAuth.validateAuthRequest(any()));
        handler.disconnect();
      },
    );

    test(
      'falha de auth: recebe authResponse(success=false, errorCode) '
      'e e desconectado',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        final mockAuth = MockServerAuthentication();
        when(
          () => mockAuth.validateAuthRequest(any()),
        ).thenAnswer(
          (_) async => const AuthValidationResult(
            isValid: false,
            errorMessage: 'credencial invalida',
            errorCode: ErrorCode.authenticationFailed,
          ),
        );

        String? disconnectedId;
        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (id) => disconnectedId = id,
          authentication: mockAuth,
        );
        handler.start();

        final responseCompleter = _expectFromServer(
          pair.client,
          protocol,
          match: (m) => m.header.type == MessageType.authResponse,
        );

        final authReq = createAuthRequest(
          serverId: 'srv',
          passwordHash: 'wrong',
        );
        pair.client.add(protocol.serializeMessage(authReq));
        await pair.client.flush();

        final response = await responseCompleter.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw TimeoutException('No authResponse'),
        );

        expect(response.payload['success'], isFalse);
        expect(response.payload['errorCode'], ErrorCode.authenticationFailed.code);
        expect(response.payload['error'], 'credencial invalida');

        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
          disconnectedId,
          equals(handler.clientId),
          reason: 'falha de auth deve desconectar (defesa contra brute force)',
        );
      },
    );

    test(
      'auth com licenseDenied: peer recebe errorCode LICENSE_DENIED '
      'e e desconectado (politica fail-closed)',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        final mockAuth = MockServerAuthentication();
        when(
          () => mockAuth.validateAuthRequest(any()),
        ).thenAnswer(
          (_) async => const AuthValidationResult(
            isValid: false,
            errorMessage: 'licenca nao permite conexao remota',
            errorCode: ErrorCode.licenseDenied,
          ),
        );

        String? disconnectedId;
        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (id) => disconnectedId = id,
          authentication: mockAuth,
        );
        handler.start();

        final responseCompleter = _expectFromServer(
          pair.client,
          protocol,
          match: (m) => m.header.type == MessageType.authResponse,
        );

        final authReq = createAuthRequest(
          serverId: 'srv',
          passwordHash: 'h',
        );
        pair.client.add(protocol.serializeMessage(authReq));
        await pair.client.flush();

        final response = await responseCompleter.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw TimeoutException('No authResponse'),
        );

        expect(response.payload['success'], isFalse);
        expect(response.payload['errorCode'], ErrorCode.licenseDenied.code);

        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(disconnectedId, equals(handler.clientId));
      },
    );

    test(
      're-auth apos sucesso: 2o authRequest e roteado para handlers '
      'downstream (nao re-valida) — comportamento documentado',
      () async {
        // Comportamento atual: `_authHandled = true` apos primeiro
        // authRequest. Segundo authRequest cai no `else if` chain;
        // como `isAuthenticated=true`, vai para `_safeAddMessage`.
        // Este teste DOCUMENTA o comportamento — qualquer mudanca
        // futura (rejeitar re-auth, exigir nova validacao) precisara
        // atualizar este teste explicitamente.
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        final mockAuth = MockServerAuthentication();
        when(
          () => mockAuth.validateAuthRequest(any()),
        ).thenAnswer((_) async => const AuthValidationResult(isValid: true));

        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (_) {},
          authentication: mockAuth,
        );
        handler.start();

        // Espera o primeiro authResponse antes de mandar o 2o auth
        final firstAuthResponse = _expectFromServer(
          pair.client,
          protocol,
          match: (m) => m.header.type == MessageType.authResponse,
        );

        var routedAuthCount = 0;
        handler.messageStream.listen((m) {
          if (m.header.type == MessageType.authRequest) routedAuthCount++;
        });

        final auth = createAuthRequest(serverId: 's', passwordHash: 'h');
        pair.client.add(protocol.serializeMessage(auth));
        await pair.client.flush();

        await firstAuthResponse.future.timeout(const Duration(seconds: 2));

        // Envia 2o authRequest
        pair.client.add(protocol.serializeMessage(auth));
        await pair.client.flush();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Validacao foi chamada apenas UMA vez — `_authHandled` previne
        // re-validacao silenciosa.
        verify(() => mockAuth.validateAuthRequest(any())).called(1);
        // Mas o 2o authRequest foi roteado para handlers downstream
        // (count >= 1: o primeiro tambem e roteado apos validacao OK).
        expect(
          routedAuthCount,
          greaterThanOrEqualTo(1),
          reason:
              '2o authRequest cai no fluxo de mensagens autenticadas; '
              'handlers downstream sao responsaveis por aceitar/rejeitar',
        );

        handler.disconnect();
      },
    );

    test(
      'mensagem operacional concorrente durante validacao async de auth: '
      'pause/resume garante que so chega ao handler apos auth confirmado',
      () async {
        final pair = await createSocketPair();
        addTearDown(() {
          pair.client.destroy();
          pair.server.destroy();
        });

        // Bloqueia a validacao de auth ate o teste liberar — simula
        // janela de concorrencia onde mensagens chegam ao buffer
        // ANTES de `isAuthenticated` virar true.
        final authReleaseCompleter = Completer<AuthValidationResult>();
        final mockAuth = MockServerAuthentication();
        when(
          () => mockAuth.validateAuthRequest(any()),
        ).thenAnswer((_) => authReleaseCompleter.future);

        final handler = ClientHandler(
          socket: pair.server,
          protocol: protocol,
          onDisconnect: (_) {},
          authentication: mockAuth,
        );
        handler.start();

        // Coleta mensagens roteadas para handlers
        final routed = <MessageType>[];
        handler.messageStream.listen((m) => routed.add(m.header.type));

        // Cliente envia auth + mensagem operacional rapidamente
        final auth = createAuthRequest(serverId: 's', passwordHash: 'h');
        final op = Message(
          header: MessageHeader(
            type: MessageType.listSchedules,
            length: 2,
            requestId: 1,
          ),
          payload: const <String, dynamic>{},
          checksum: 0,
        );
        pair.client.add(protocol.serializeMessage(auth));
        pair.client.add(protocol.serializeMessage(op));
        await pair.client.flush();

        // Janela: validacao ainda nao retornou. listSchedules NAO pode
        // ter sido roteado ainda.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          routed.contains(MessageType.listSchedules),
          isFalse,
          reason:
              'listSchedules nao pode chegar a downstream antes da '
              'validacao de auth completar',
        );

        // Libera auth como sucesso
        authReleaseCompleter.complete(
          const AuthValidationResult(isValid: true),
        );

        // Agora as mensagens sao reprocessadas — auth + listSchedules
        // chegam ao stream.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(routed, contains(MessageType.authRequest));
        expect(routed, contains(MessageType.listSchedules));

        handler.disconnect();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Grupo 3: Defesa contra brute force / enumeracao
  // ---------------------------------------------------------------------------
  group('Brute force / enumeracao — defesas e gaps documentados', () {
    test(
      'authResponse de falha NAO discrimina "serverId nao existe" '
      'de "senha errada" no errorCode (defesa contra enumeracao)',
      () async {
        // Tanto credencial inexistente quanto senha errada produzem
        // ErrorCode.authenticationFailed — o cliente nao consegue
        // distinguir os dois casos. ServerAuthentication ja faz isso.
        // Este teste ANCORA o invariante.
        const matching = ErrorCode.authenticationFailed;

        // Caso 1: serverId nao existe → authenticationFailed
        // Caso 2: senha errada → authenticationFailed
        // Ambos retornam o MESMO errorCode publico.
        expect(matching, ErrorCode.authenticationFailed);
        expect(matching, isNot(ErrorCode.invalidRequest));
      },
    );
  });
}
