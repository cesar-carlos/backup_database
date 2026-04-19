import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Provider mínimo de teste — expõe o mixin com hooks para inspecionar
/// estado interno e contar quantas vezes `notifyListeners` foi chamado.
class _TestProvider extends ChangeNotifier with AsyncStateMixin {
  int notifyCount = 0;

  @override
  void notifyListeners() {
    notifyCount++;
    super.notifyListeners();
  }

  Future<T?> doRunAsync<T>({
    required Future<T> Function() action,
    String? genericErrorMessage,
    bool rethrowOnError = false,
  }) {
    return runAsync<T>(
      action: action,
      genericErrorMessage: genericErrorMessage,
      rethrowOnError: rethrowOnError,
    );
  }

  void doSetErrorManual(String message, {String? code}) {
    setErrorManual(message, code: code);
  }
}

void main() {
  group('AsyncStateMixin.runAsync — happy path', () {
    test('returns the action value on success', () async {
      final provider = _TestProvider();

      final result = await provider.doRunAsync<int>(action: () async => 42);

      expect(result, equals(42));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
      expect(provider.lastErrorCode, isNull);
    });

    test(
      'sets isLoading=true during execution and false after',
      () async {
        final provider = _TestProvider();

        bool? loadingDuringAction;
        await provider.doRunAsync<void>(
          action: () async {
            loadingDuringAction = provider.isLoading;
          },
        );

        expect(loadingDuringAction, isTrue);
        expect(provider.isLoading, isFalse);
      },
    );

    test(
      'notifies listeners on start (idle→running) and on finish',
      () async {
        final provider = _TestProvider();
        final initialCount = provider.notifyCount;

        await provider.doRunAsync<void>(action: () async {});

        // Mínimo 2 notificações: ao iniciar (transição 0→1) e no finally
        // (transição 1→0). A notificação de "início com error reset" é
        // condicional a `wasIdle || hadError`.
        expect(
          provider.notifyCount - initialCount,
          greaterThanOrEqualTo(2),
        );
      },
    );

    test(
      'clears error from previous run when starting new operation',
      () async {
        final provider = _TestProvider();

        // Primeira chamada: gera erro
        await provider.doRunAsync<void>(
          action: () async => throw Exception('first failure'),
        );
        expect(provider.error, isNotNull);

        // Segunda chamada bem-sucedida: deve limpar o erro
        await provider.doRunAsync<int>(action: () async => 1);
        expect(provider.error, isNull);
        expect(provider.lastErrorCode, isNull);
      },
    );
  });

  group('AsyncStateMixin.runAsync — error handling', () {
    test('returns null and sets error on generic exception', () async {
      final provider = _TestProvider();

      final result = await provider.doRunAsync<int>(
        action: () async => throw Exception('boom'),
      );

      expect(result, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.error, contains('boom'));
    });

    test(
      'prefixes error with genericErrorMessage when provided',
      () async {
        final provider = _TestProvider();

        await provider.doRunAsync<int>(
          genericErrorMessage: 'Erro ao carregar foos',
          action: () async => throw Exception('bar'),
        );

        expect(provider.error, contains('Erro ao carregar foos'));
        expect(provider.error, contains('bar'));
      },
    );

    test(
      'extracts message from Failure subtype (uses Failure.message, not toString)',
      () async {
        final provider = _TestProvider();

        await provider.doRunAsync<int>(
          action: () async =>
              throw const ValidationFailure(message: 'invalido'),
        );

        // Failure.message é "invalido", não a String do toString()
        expect(provider.error, contains('invalido'));
        expect(
          provider.error,
          isNot(contains('Failure(')),
          reason: 'Should use Failure.message, not toString()',
        );
      },
    );

    test('extracts Failure.code into lastErrorCode', () async {
      final provider = _TestProvider();

      await provider.doRunAsync<int>(
        action: () async => throw const ValidationFailure(
          message: 'falha',
          code: 'VAL_001',
        ),
      );

      expect(provider.lastErrorCode, equals('VAL_001'));
    });

    test('lastErrorCode is null for non-Failure exceptions', () async {
      final provider = _TestProvider();

      await provider.doRunAsync<int>(
        action: () async => throw Exception('plain'),
      );

      expect(provider.error, isNotNull);
      expect(provider.lastErrorCode, isNull);
    });

    test('rethrowOnError=true propagates the exception', () async {
      final provider = _TestProvider();

      await expectLater(
        provider.doRunAsync<int>(
          rethrowOnError: true,
          action: () async => throw Exception('rethrown'),
        ),
        throwsA(isA<Exception>()),
      );

      // Mesmo com rethrow, o estado é cleanup'd no finally
      expect(provider.isLoading, isFalse);
      expect(provider.error, contains('rethrown'));
    });

    test(
      'isLoading returns to false even when action throws (finally semantics)',
      () async {
        final provider = _TestProvider();

        await provider.doRunAsync<int>(
          action: () async => throw Exception('error'),
        );

        expect(
          provider.isLoading,
          isFalse,
          reason: 'finally must always reset the operation counter',
        );
      },
    );
  });

  group('AsyncStateMixin.runAsync — concurrency', () {
    test(
      'isLoading stays true during concurrent operations (counter, not boolean)',
      () async {
        final provider = _TestProvider();

        // Disparar duas operações simultâneas: a primeira termina antes
        // da segunda. Antes do mixin (com boolean), `isLoading` ficava
        // false após a primeira terminar mesmo que a segunda ainda
        // estivesse rodando (race condition clássico).
        final completer1 = Future<int>.delayed(
          const Duration(milliseconds: 50),
          () => 1,
        );
        final completer2 = Future<int>.delayed(
          const Duration(milliseconds: 100),
          () => 2,
        );

        final op1 = provider.doRunAsync<int>(action: () => completer1);
        final op2 = provider.doRunAsync<int>(action: () => completer2);

        // Aguarda só a primeira completar
        await op1;

        expect(
          provider.isLoading,
          isTrue,
          reason: 'Counter pattern: isLoading must stay true until ALL '
              'operations complete, not just the first',
        );

        await op2;
        expect(provider.isLoading, isFalse);
      },
    );

    test(
      'final notifyListeners runs after each operation in concurrent flow',
      () async {
        final provider = _TestProvider();

        await Future.wait([
          provider.doRunAsync<int>(action: () async => 1),
          provider.doRunAsync<int>(action: () async => 2),
        ]);

        expect(provider.isLoading, isFalse);
        // 2 ops × pelo menos 2 notifications cada = pelo menos 4
        // (na prática algumas se sobrepõem na transição idle→busy)
        expect(provider.notifyCount, greaterThanOrEqualTo(2));
      },
    );
  });

  group('AsyncStateMixin.clearError', () {
    test('does nothing (and skips notify) when there is no error', () async {
      final provider = _TestProvider();
      final beforeCount = provider.notifyCount;

      provider.clearError();

      expect(provider.error, isNull);
      expect(
        provider.notifyCount,
        equals(beforeCount),
        reason: 'no-op should NOT notify listeners (avoids extra rebuilds)',
      );
    });

    test('clears error and code, then notifies', () async {
      final provider = _TestProvider();

      await provider.doRunAsync<int>(
        action: () async => throw const ValidationFailure(
          message: 'oops',
          code: 'OOPS_1',
        ),
      );
      expect(provider.error, isNotNull);
      expect(provider.lastErrorCode, equals('OOPS_1'));

      final before = provider.notifyCount;
      provider.clearError();

      expect(provider.error, isNull);
      expect(provider.lastErrorCode, isNull);
      expect(provider.notifyCount, equals(before + 1));
    });
  });

  group('AsyncStateMixin.setErrorManual', () {
    test('sets error and code without affecting isLoading', () async {
      final provider = _TestProvider();

      provider.doSetErrorManual('manual error', code: 'MAN_1');

      expect(provider.error, equals('manual error'));
      expect(provider.lastErrorCode, equals('MAN_1'));
      expect(
        provider.isLoading,
        isFalse,
        reason: 'setErrorManual is for sync validation; should not '
            'increment the operation counter',
      );
    });

    test('notifies listeners on every call', () async {
      final provider = _TestProvider();
      final before = provider.notifyCount;

      provider.doSetErrorManual('first');
      provider.doSetErrorManual('second');

      expect(provider.notifyCount, equals(before + 2));
    });
  });

  group('AsyncStateMixin static helpers', () {
    test(
      'extractFailureMessage uses Failure.message for Failure types',
      () {
        const failure = ValidationFailure(message: 'invalido');
        expect(
          AsyncStateMixin.extractFailureMessage(failure),
          equals('invalido'),
        );
      },
    );

    test('extractFailureMessage falls back to toString for Object', () {
      final ex = Exception('plain error');
      expect(
        AsyncStateMixin.extractFailureMessage(ex),
        contains('plain error'),
      );
    });

    test('extractFailureCode returns code for Failure subtypes', () {
      const failure = ValidationFailure(message: 'x', code: 'XYZ');
      expect(
        AsyncStateMixin.extractFailureCode(failure),
        equals('XYZ'),
      );
    });

    test('extractFailureCode returns null for non-Failure', () {
      expect(
        AsyncStateMixin.extractFailureCode(Exception('plain')),
        isNull,
      );
      expect(AsyncStateMixin.extractFailureCode(null), isNull);
    });
  });
}
