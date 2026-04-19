import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/socket/server/execution_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExecutionStateMachine.canTransition', () {
    test('queued -> running permitida', () {
      expect(
        ExecutionStateMachine.canTransition(
          ExecutionState.queued,
          ExecutionState.running,
        ),
        isTrue,
      );
    });

    test('queued -> cancelled permitida (cancelQueuedBackup)', () {
      expect(
        ExecutionStateMachine.canTransition(
          ExecutionState.queued,
          ExecutionState.cancelled,
        ),
        isTrue,
      );
    });

    test('running -> completed permitida', () {
      expect(
        ExecutionStateMachine.canTransition(
          ExecutionState.running,
          ExecutionState.completed,
        ),
        isTrue,
      );
    });

    test('running -> failed permitida', () {
      expect(
        ExecutionStateMachine.canTransition(
          ExecutionState.running,
          ExecutionState.failed,
        ),
        isTrue,
      );
    });

    test('running -> cancelled permitida (cancelBackup)', () {
      expect(
        ExecutionStateMachine.canTransition(
          ExecutionState.running,
          ExecutionState.cancelled,
        ),
        isTrue,
      );
    });

    test('queued -> queued PROIBIDA (sem self-loops)', () {
      expect(
        ExecutionStateMachine.canTransition(
          ExecutionState.queued,
          ExecutionState.queued,
        ),
        isFalse,
      );
    });

    test('queued -> completed PROIBIDA (precisa passar por running)', () {
      expect(
        ExecutionStateMachine.canTransition(
          ExecutionState.queued,
          ExecutionState.completed,
        ),
        isFalse,
      );
    });

    test('queued -> failed PROIBIDA (precisa passar por running)', () {
      expect(
        ExecutionStateMachine.canTransition(
          ExecutionState.queued,
          ExecutionState.failed,
        ),
        isFalse,
      );
    });

    test('completed -> qualquer outro estado PROIBIDA (terminal)', () {
      for (final to in ExecutionState.values) {
        expect(
          ExecutionStateMachine.canTransition(ExecutionState.completed, to),
          isFalse,
          reason: 'completed -> ${to.name} nao deveria ser permitida',
        );
      }
    });

    test('failed -> qualquer outro estado PROIBIDA (terminal)', () {
      for (final to in ExecutionState.values) {
        expect(
          ExecutionStateMachine.canTransition(ExecutionState.failed, to),
          isFalse,
        );
      }
    });

    test('cancelled -> qualquer outro estado PROIBIDA (terminal)', () {
      for (final to in ExecutionState.values) {
        expect(
          ExecutionStateMachine.canTransition(ExecutionState.cancelled, to),
          isFalse,
        );
      }
    });

    test('notFound -> qualquer estado PROIBIDA (nao modelado)', () {
      for (final to in ExecutionState.values) {
        expect(
          ExecutionStateMachine.canTransition(ExecutionState.notFound, to),
          isFalse,
        );
      }
    });

    test('unknown -> qualquer estado PROIBIDA (nao modelado)', () {
      for (final to in ExecutionState.values) {
        expect(
          ExecutionStateMachine.canTransition(ExecutionState.unknown, to),
          isFalse,
        );
      }
    });
  });

  group('ExecutionStateMachine.enforceTransition', () {
    test('transicao permitida nao lanca', () {
      expect(
        () => ExecutionStateMachine.enforceTransition(
          ExecutionState.running,
          ExecutionState.completed,
        ),
        returnsNormally,
      );
    });

    test('transicao proibida lanca InvalidStateTransitionException', () {
      expect(
        () => ExecutionStateMachine.enforceTransition(
          ExecutionState.completed,
          ExecutionState.running,
        ),
        throwsA(isA<InvalidStateTransitionException>()),
      );
    });

    test('mensagem da excecao inclui from -> to para diagnostico', () {
      try {
        ExecutionStateMachine.enforceTransition(
          ExecutionState.queued,
          ExecutionState.failed,
        );
        fail('expected throw');
      } on InvalidStateTransitionException catch (e) {
        expect(e.toString(), contains('queued'));
        expect(e.toString(), contains('failed'));
      }
    });
  });

  group('ExecutionStateMachine.isTerminal', () {
    test('completed e terminal', () {
      expect(
        ExecutionStateMachine.isTerminal(ExecutionState.completed),
        isTrue,
      );
    });

    test('failed e terminal', () {
      expect(ExecutionStateMachine.isTerminal(ExecutionState.failed), isTrue);
    });

    test('cancelled e terminal', () {
      expect(
        ExecutionStateMachine.isTerminal(ExecutionState.cancelled),
        isTrue,
      );
    });

    test('queued NAO e terminal', () {
      expect(ExecutionStateMachine.isTerminal(ExecutionState.queued), isFalse);
    });

    test('running NAO e terminal', () {
      expect(ExecutionStateMachine.isTerminal(ExecutionState.running), isFalse);
    });

    test('notFound nem unknown NAO sao tratados como terminais', () {
      // Sao meta-estados — cliente decide o que fazer.
      expect(ExecutionStateMachine.isTerminal(ExecutionState.notFound), isFalse);
      expect(ExecutionStateMachine.isTerminal(ExecutionState.unknown), isFalse);
    });
  });

  group('ExecutionStateMachine.allowedFrom', () {
    test('queued -> {running, cancelled}', () {
      final allowed = ExecutionStateMachine.allowedFrom(ExecutionState.queued);
      expect(allowed, {ExecutionState.running, ExecutionState.cancelled});
    });

    test('running -> {completed, failed, cancelled}', () {
      final allowed = ExecutionStateMachine.allowedFrom(ExecutionState.running);
      expect(allowed, {
        ExecutionState.completed,
        ExecutionState.failed,
        ExecutionState.cancelled,
      });
    });

    test('estados terminais retornam Set vazio', () {
      expect(
        ExecutionStateMachine.allowedFrom(ExecutionState.completed),
        isEmpty,
      );
      expect(
        ExecutionStateMachine.allowedFrom(ExecutionState.failed),
        isEmpty,
      );
      expect(
        ExecutionStateMachine.allowedFrom(ExecutionState.cancelled),
        isEmpty,
      );
    });

    test('Set retornado e unmodifiable', () {
      final allowed = ExecutionStateMachine.allowedFrom(ExecutionState.running);
      expect(
        () => allowed.add(ExecutionState.queued),
        throwsUnsupportedError,
      );
    });
  });

  group('Caso de uso: UI que mostra acoes disponiveis', () {
    test('execucao em queued: mostrar botao Cancelar (cancelQueuedBackup)', () {
      final allowed = ExecutionStateMachine.allowedFrom(ExecutionState.queued);
      expect(allowed, contains(ExecutionState.cancelled));
    });

    test('execucao em running: mostrar botao Cancelar (cancelBackup)', () {
      final allowed = ExecutionStateMachine.allowedFrom(ExecutionState.running);
      expect(allowed, contains(ExecutionState.cancelled));
    });

    test(
      'execucao terminal: nenhuma acao disponivel — UI fecha card',
      () {
        for (final terminal in [
          ExecutionState.completed,
          ExecutionState.failed,
          ExecutionState.cancelled,
        ]) {
          expect(
            ExecutionStateMachine.allowedFrom(terminal),
            isEmpty,
            reason: 'terminal ${terminal.name}',
          );
        }
      },
    );
  });
}
