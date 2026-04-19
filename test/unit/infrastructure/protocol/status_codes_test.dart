import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/status_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatusCodes (F0.5 / F0.6 / P1.2)', () {
    test('constantes seguem semantica HTTP padrao', () {
      expect(StatusCodes.ok, 200);
      expect(StatusCodes.accepted, 202);
      expect(StatusCodes.badRequest, 400);
      expect(StatusCodes.unauthorized, 401);
      expect(StatusCodes.forbidden, 403);
      expect(StatusCodes.notFound, 404);
      expect(StatusCodes.conflict, 409);
      expect(StatusCodes.gone, 410);
      expect(StatusCodes.unprocessableEntity, 422);
      expect(StatusCodes.tooManyRequests, 429);
      expect(StatusCodes.internalServerError, 500);
      expect(StatusCodes.serviceUnavailable, 503);
    });

    group('forErrorCode mapping', () {
      test('codigos de validacao -> 400', () {
        expect(
          StatusCodes.forErrorCode(ErrorCode.invalidRequest),
          StatusCodes.badRequest,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.parseError),
          StatusCodes.badRequest,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.payloadTooLarge),
          StatusCodes.badRequest,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.invalidChecksum),
          StatusCodes.badRequest,
        );
      });

      test('falha de auth -> 401', () {
        expect(
          StatusCodes.forErrorCode(ErrorCode.authenticationFailed),
          StatusCodes.unauthorized,
        );
      });

      test('licensa/permissao/path -> 403', () {
        expect(
          StatusCodes.forErrorCode(ErrorCode.licenseDenied),
          StatusCodes.forbidden,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.permissionDenied),
          StatusCodes.forbidden,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.pathNotAllowed),
          StatusCodes.forbidden,
        );
      });

      test('not found -> 404', () {
        expect(
          StatusCodes.forErrorCode(ErrorCode.fileNotFound),
          StatusCodes.notFound,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.directoryNotFound),
          StatusCodes.notFound,
        );
      });

      test('conflito de estado -> 409', () {
        expect(
          StatusCodes.forErrorCode(ErrorCode.fileBusy),
          StatusCodes.conflict,
        );
      });

      test('servico/pre-requisito -> 503', () {
        expect(
          StatusCodes.forErrorCode(ErrorCode.unsupportedProtocolVersion),
          StatusCodes.serviceUnavailable,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.diskFull),
          StatusCodes.serviceUnavailable,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.ioError),
          StatusCodes.serviceUnavailable,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.connectionLost),
          StatusCodes.serviceUnavailable,
        );
        expect(
          StatusCodes.forErrorCode(ErrorCode.timeout),
          StatusCodes.serviceUnavailable,
        );
      });

      test('unknown -> 500 (fail-safe)', () {
        expect(
          StatusCodes.forErrorCode(ErrorCode.unknown),
          StatusCodes.internalServerError,
        );
      });
    });

    test('todos os ErrorCode tem entrada no mapping', () {
      // Garante que adicionar novo ErrorCode nao deixa lacuna sem
      // mapping — seria fail-safe via fallback 500, mas teste explicito
      // evita que escape em revisao.
      final missing = ErrorCode.values
          .where((e) => !StatusCodes.all.containsKey(e))
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'ErrorCode(s) sem mapping em StatusCodes.forErrorCode: '
            '${missing.map((e) => e.name).join(', ')}. '
            'Adicione em StatusCodes._byErrorCode ou justifique fallback 500.',
      );
    });

    group('helpers de classificacao', () {
      test('isSuccess cobre 2xx', () {
        expect(StatusCodes.isSuccess(200), isTrue);
        expect(StatusCodes.isSuccess(202), isTrue);
        expect(StatusCodes.isSuccess(299), isTrue);
        expect(StatusCodes.isSuccess(300), isFalse);
        expect(StatusCodes.isSuccess(199), isFalse);
        expect(StatusCodes.isSuccess(400), isFalse);
      });

      test('isClientError cobre 4xx', () {
        expect(StatusCodes.isClientError(400), isTrue);
        expect(StatusCodes.isClientError(404), isTrue);
        expect(StatusCodes.isClientError(429), isTrue);
        expect(StatusCodes.isClientError(499), isTrue);
        expect(StatusCodes.isClientError(500), isFalse);
        expect(StatusCodes.isClientError(200), isFalse);
      });

      test('isServerError cobre 5xx', () {
        expect(StatusCodes.isServerError(500), isTrue);
        expect(StatusCodes.isServerError(503), isTrue);
        expect(StatusCodes.isServerError(599), isTrue);
        expect(StatusCodes.isServerError(400), isFalse);
        expect(StatusCodes.isServerError(600), isFalse);
      });

      test('isRetryable cobre 5xx + 429', () {
        expect(StatusCodes.isRetryable(500), isTrue);
        expect(StatusCodes.isRetryable(503), isTrue);
        expect(StatusCodes.isRetryable(429), isTrue);
        // 4xx (exceto 429) nao deve ser retryable: cliente precisa
        // corrigir o request, nao retentar
        expect(StatusCodes.isRetryable(400), isFalse);
        expect(StatusCodes.isRetryable(401), isFalse);
        expect(StatusCodes.isRetryable(404), isFalse);
        expect(StatusCodes.isRetryable(409), isFalse);
        expect(StatusCodes.isRetryable(200), isFalse);
      });
    });

    test('all retorna mapa imutavel (defesa)', () {
      final map = StatusCodes.all;
      expect(
        () => map[ErrorCode.unknown] = 999,
        throwsUnsupportedError,
      );
    });
  });
}
