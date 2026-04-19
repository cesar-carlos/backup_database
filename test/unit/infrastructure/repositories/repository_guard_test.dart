import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart' as rd;

void main() {
  group('RepositoryGuard.run', () {
    test('returns Success when action completes normally', () async {
      final result = await RepositoryGuard.run<String>(
        errorMessage: 'Erro ao buscar',
        action: () async => 'hello',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), equals('hello'));
    });

    test(
      'wraps non-Failure exception in DatabaseFailure with originalError',
      () async {
        final originalException = StateError('boom');

        final result = await RepositoryGuard.run<String>(
          errorMessage: 'Erro ao buscar',
          logErrors: false,
          action: () async => throw originalException,
        );

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        expect(failure, isA<DatabaseFailure>());
        final dbFailure = failure! as DatabaseFailure;
        expect(dbFailure.message, contains('Erro ao buscar'));
        expect(dbFailure.message, contains('boom'));
        expect(
          dbFailure.originalError,
          same(originalException),
          reason: 'originalError should be preserved for diagnostics',
        );
      },
    );

    test('passes Failure subtype through unchanged (NotFoundFailure)', () async {
      const semanticFailure = NotFoundFailure(
        message: 'Registro não encontrado',
      );

      final result = await RepositoryGuard.run<String>(
        errorMessage: 'Erro ao buscar',
        logErrors: false,
        action: () async => throw semanticFailure,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(
        failure,
        isA<NotFoundFailure>(),
        reason:
            'RepositoryGuard must passthrough Failure subtypes to preserve '
            'semantics; otherwise NotFoundFailure becomes DatabaseFailure',
      );
      expect((failure! as NotFoundFailure).message, equals(semanticFailure.message));
    });

    test('passes Failure subtype through unchanged (ValidationFailure)', () async {
      const semanticFailure = ValidationFailure(
        message: 'Transição inválida',
      );

      final result = await RepositoryGuard.run<String>(
        errorMessage: 'Erro ao atualizar',
        logErrors: false,
        action: () async => throw semanticFailure,
      );

      expect(result.exceptionOrNull(), isA<ValidationFailure>());
    });

    test(
      'failureBuilder customizes wrap type for non-Failure exceptions',
      () async {
        final result = await RepositoryGuard.run<String>(
          errorMessage: 'Erro de rede',
          logErrors: false,
          failureBuilder: (msg, original) => NetworkFailure(
            message: msg,
            originalError: original,
          ),
          action: () async => throw Exception('connection refused'),
        );

        expect(result.exceptionOrNull(), isA<NetworkFailure>());
      },
    );

    test('failureBuilder is NOT used when action throws a Failure', () async {
      const semanticFailure = ValidationFailure(message: 'invalid');

      var builderCalled = false;
      final result = await RepositoryGuard.run<String>(
        errorMessage: 'Erro',
        logErrors: false,
        failureBuilder: (msg, original) {
          builderCalled = true;
          return NetworkFailure(message: msg);
        },
        action: () async => throw semanticFailure,
      );

      expect(
        builderCalled,
        isFalse,
        reason: 'failureBuilder is for wrapping non-Failure throws only; '
            'Failure types passthrough untouched',
      );
      expect(result.exceptionOrNull(), isA<ValidationFailure>());
    });

    test('rethrows synchronous errors from action body', () async {
      // Verifica que mesmo se o action lançar antes do primeiro `await`,
      // o guard captura corretamente (zonas async de Dart).
      final result = await RepositoryGuard.run<int>(
        errorMessage: 'Erro síncrono',
        logErrors: false,
        // Testa `throw` de tipo não-Exception (String) para garantir
        // que o guard ainda captura e wrappa em DatabaseFailure.
        // ignore: only_throw_errors
        action: () async => throw 'string-as-error',
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<DatabaseFailure>());
    });
  });

  group('RepositoryGuard.runVoid', () {
    test('returns Success(unit) when action completes', () async {
      var sideEffectRan = false;
      final result = await RepositoryGuard.runVoid(
        errorMessage: 'Erro',
        action: () async {
          sideEffectRan = true;
        },
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), equals(unit));
      expect(sideEffectRan, isTrue);
    });

    test('wraps exception in DatabaseFailure', () async {
      final result = await RepositoryGuard.runVoid(
        errorMessage: 'Erro ao deletar',
        logErrors: false,
        action: () async => throw Exception('disk full'),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<DatabaseFailure>());
      expect((failure! as DatabaseFailure).message, contains('disk full'));
    });

    test('passes Failure subtype through unchanged', () async {
      final result = await RepositoryGuard.runVoid(
        errorMessage: 'Erro ao deletar',
        logErrors: false,
        action: () async =>
            throw const NotFoundFailure(message: 'sumiu'),
      );

      expect(result.exceptionOrNull(), isA<NotFoundFailure>());
    });
  });

  group('RepositoryGuard end-to-end (caller perspective)', () {
    test(
      'caller can pattern-match on Failure subtype to decide retry vs. user-feedback',
      () async {
        // Simula um caller real: query falha, ele precisa decidir se mostra
        // "registro não existe" (NotFound) vs. "erro de I/O, tente de novo"
        // (DatabaseFailure). Esta era a motivação central do passthrough.
        Future<rd.Result<String>> guarded(int input) {
          return RepositoryGuard.run<String>(
            errorMessage: 'Erro ao buscar',
            logErrors: false,
            action: () async {
              if (input == 0) {
                throw const NotFoundFailure(message: 'Vazio');
              }
              if (input < 0) {
                throw Exception('I/O failure');
              }
              return 'value=$input';
            },
          );
        }

        final notFound = await guarded(0);
        final ioError = await guarded(-1);
        final ok = await guarded(42);

        expect(notFound.exceptionOrNull(), isA<NotFoundFailure>());
        expect(ioError.exceptionOrNull(), isA<DatabaseFailure>());
        expect(ok.getOrNull(), equals('value=42'));
      },
    );
  });
}
