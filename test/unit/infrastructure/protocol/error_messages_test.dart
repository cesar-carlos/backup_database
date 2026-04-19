import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('createErrorMessage envelope (F0.5/F0.6)', () {
    test(
      'sem errorCode -> statusCode default 500 (fail-safe)',
      () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'algo deu errado',
        );

        expect(msg.header.type, MessageType.error);
        expect(msg.payload['error'], 'algo deu errado');
        expect(msg.payload['statusCode'], StatusCodes.internalServerError);
        expect(msg.payload.containsKey('errorCode'), isFalse);
      },
    );

    test(
      'com errorCode -> statusCode derivado da tabela oficial',
      () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'Path nao permitido',
          errorCode: ErrorCode.pathNotAllowed,
        );

        expect(msg.payload['errorCode'], 'PATH_NOT_ALLOWED');
        expect(msg.payload['statusCode'], StatusCodes.forbidden);
        // Sanity: 403
        expect(msg.payload['statusCode'], 403);
      },
    );

    test(
      'auth failure -> 401',
      () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'credenciais invalidas',
          errorCode: ErrorCode.authenticationFailed,
        );
        expect(msg.payload['statusCode'], 401);
      },
    );

    test(
      'unsupported wire version -> 503',
      () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'wire v99 nao suportada',
          errorCode: ErrorCode.unsupportedProtocolVersion,
        );
        expect(msg.payload['statusCode'], 503);
      },
    );

    test(
      'payloadTooLarge -> 400 (e nao 413 — escolhemos 400 generico)',
      () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'payload demais',
          errorCode: ErrorCode.payloadTooLarge,
        );
        expect(msg.payload['statusCode'], 400);
      },
    );

    test(
      'statusCodeOverride permite forcar codigo nao-padrao',
      () {
        // Cenario: handler quer diferenciar 409 BACKUP_ALREADY_RUNNING
        // de 409 INVALID_STATE_TRANSITION quando um eventualmente
        // mapear para 422 ou similar. Override permite.
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'sessao expirou',
          errorCode: ErrorCode.unknown,
          statusCodeOverride: StatusCodes.gone,
        );
        expect(msg.payload['statusCode'], 410);
      },
    );

    test(
      'getStatusCodeFromMessage le valor int do payload',
      () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'x',
          errorCode: ErrorCode.fileBusy,
        );
        expect(getStatusCodeFromMessage(msg), 409);
      },
    );

    test(
      'getStatusCodeFromMessage retorna null em payload v1 sem statusCode',
      () {
        // Simula servidor v1 que nao envia statusCode
        final msg = Message(
          header: MessageHeader(
            type: MessageType.error,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{
            'error': 'erro legado',
          },
          checksum: 0,
        );
        expect(getStatusCodeFromMessage(msg), isNull);
      },
    );

    test(
      'getStatusCodeFromMessage tolera valor num (JSON pode trazer double)',
      () {
        final msg = Message(
          header: MessageHeader(
            type: MessageType.error,
            length: 0,
            requestId: 1,
          ),
          payload: const <String, dynamic>{
            'error': 'x',
            'statusCode': 503.0, // double, simula JSON parser variando
          },
          checksum: 0,
        );
        expect(getStatusCodeFromMessage(msg), 503);
      },
    );

    test(
      'getErrorCodeFromMessage e getErrorFromMessage continuam funcionando',
      () {
        final msg = createErrorMessage(
          requestId: 1,
          errorMessage: 'sem disco',
          errorCode: ErrorCode.diskFull,
        );
        expect(getErrorFromMessage(msg), 'sem disco');
        expect(getErrorCodeFromMessage(msg), ErrorCode.diskFull);
      },
    );

    test(
      'envelope sempre inclui statusCode (mesmo sem errorCode) — '
      'cliente pode montar mapa de retry baseado so em statusCode',
      () {
        final m1 = createErrorMessage(
          requestId: 1,
          errorMessage: 'x',
        );
        expect(m1.payload.containsKey('statusCode'), isTrue);

        final m2 = createErrorMessage(
          requestId: 1,
          errorMessage: 'x',
          errorCode: ErrorCode.timeout,
        );
        expect(m2.payload.containsKey('statusCode'), isTrue);
      },
    );
  });
}
