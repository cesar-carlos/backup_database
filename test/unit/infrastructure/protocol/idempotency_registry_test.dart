import 'dart:async';

import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdempotencyRegistry', () {
    test('sem chave: compute SEMPRE roda (idempotencia opt-in)', () async {
      final registry = IdempotencyRegistry();
      var calls = 0;
      Future<int> compute() async {
        calls++;
        return calls;
      }

      final r1 = await registry.runIdempotent(key: null, compute: compute);
      final r2 = await registry.runIdempotent(key: '', compute: compute);
      final r3 = await registry.runIdempotent(key: null, compute: compute);
      expect(r1, 1);
      expect(r2, 2);
      expect(r3, 3);
      expect(calls, 3);
    });

    test('mesma chave: compute roda APENAS na primeira chamada', () async {
      final registry = IdempotencyRegistry();
      var calls = 0;

      final results = <int>[];
      for (var i = 0; i < 5; i++) {
        final r = await registry.runIdempotent<int>(
          key: 'k',
          compute: () async {
            calls++;
            return 100 + calls;
          },
        );
        results.add(r);
      }
      expect(calls, 1);
      expect(results, List.filled(5, 101));
    });

    test('chaves diferentes: cada uma tem seu proprio cache', () async {
      final registry = IdempotencyRegistry();
      var calls = 0;
      Future<int> compute() async => ++calls;

      final a1 = await registry.runIdempotent(key: 'A', compute: compute);
      final b1 = await registry.runIdempotent(key: 'B', compute: compute);
      final a2 = await registry.runIdempotent(key: 'A', compute: compute);
      final b2 = await registry.runIdempotent(key: 'B', compute: compute);
      expect(a1, 1);
      expect(b1, 2);
      expect(a2, 1);
      expect(b2, 2);
      expect(calls, 2);
    });

    test('TTL: apos expiracao, compute roda novamente', () async {
      var fakeNow = DateTime.utc(2026, 1, 1, 12);
      final registry = IdempotencyRegistry(
        ttl: const Duration(seconds: 30),
        clock: () => fakeNow,
      );
      var calls = 0;

      final r1 = await registry.runIdempotent<int>(
        key: 'k',
        compute: () async => ++calls,
      );
      // Avanca o relogio alem do TTL
      fakeNow = fakeNow.add(const Duration(minutes: 1));
      final r2 = await registry.runIdempotent<int>(
        key: 'k',
        compute: () async => ++calls,
      );
      expect(r1, 1);
      expect(r2, 2);
    });

    test(
      'requests concorrentes com mesma chave: compute roda APENAS uma vez',
      () async {
        final registry = IdempotencyRegistry();
        var calls = 0;
        final completer = Completer<int>();

        Future<int> slowCompute() async {
          calls++;
          return completer.future;
        }

        final futures = List.generate(
          10,
          (_) => registry.runIdempotent(key: 'k', compute: slowCompute),
        );
        // Libera o compute
        await Future<void>.delayed(const Duration(milliseconds: 20));
        completer.complete(42);

        final results = await Future.wait(futures);
        expect(calls, 1, reason: 'compute deve rodar apenas uma vez');
        expect(results, List.filled(10, 42));
      },
    );

    test('falha em compute NAO e cacheada (cliente pode tentar de novo)',
        () async {
      final registry = IdempotencyRegistry();
      var attempt = 0;
      Future<int> failingThenSuccess() async {
        attempt++;
        if (attempt == 1) throw StateError('boom');
        return 42;
      }

      // 1a chamada: falha
      await expectLater(
        registry.runIdempotent<int>(key: 'k', compute: failingThenSuccess),
        throwsA(isA<StateError>()),
      );
      // 2a chamada: sucesso (registry NAO mantem o erro cacheado)
      final r = await registry.runIdempotent<int>(
        key: 'k',
        compute: failingThenSuccess,
      );
      expect(r, 42);
      expect(attempt, 2);
    });

    test('size respeita TTL (purge on-demand)', () async {
      var fakeNow = DateTime.utc(2026, 1, 1, 12);
      final registry = IdempotencyRegistry(
        ttl: const Duration(seconds: 10),
        clock: () => fakeNow,
      );
      await registry.runIdempotent<int>(key: 'a', compute: () async => 1);
      await registry.runIdempotent<int>(key: 'b', compute: () async => 2);
      expect(registry.size, 2);
      fakeNow = fakeNow.add(const Duration(seconds: 30));
      expect(registry.size, 0);
    });

    test('clear() esvazia o registry', () async {
      final registry = IdempotencyRegistry();
      await registry.runIdempotent<int>(key: 'a', compute: () async => 1);
      expect(registry.size, 1);
      registry.clear();
      expect(registry.size, 0);
    });

    test('chave reusada com tipo diferente -> StateError', () async {
      final registry = IdempotencyRegistry();
      await registry.runIdempotent<int>(key: 'k', compute: () async => 42);
      await expectLater(
        registry.runIdempotent<String>(
          key: 'k',
          compute: () async => 'wrong',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('getIdempotencyKey helper', () {
    test('retorna chave quando string nao-vazia', () {
      final msg = Message(
        header: MessageHeader(type: MessageType.executeSchedule, length: 0),
        payload: const <String, dynamic>{'idempotencyKey': 'abc-123'},
        checksum: 0,
      );
      expect(getIdempotencyKey(msg), 'abc-123');
    });

    test('retorna null quando ausente', () {
      final msg = Message(
        header: MessageHeader(type: MessageType.executeSchedule, length: 0),
        payload: const <String, dynamic>{'scheduleId': 'x'},
        checksum: 0,
      );
      expect(getIdempotencyKey(msg), isNull);
    });

    test('retorna null quando vazio (idempotencia opt-in)', () {
      final msg = Message(
        header: MessageHeader(type: MessageType.executeSchedule, length: 0),
        payload: const <String, dynamic>{'idempotencyKey': ''},
        checksum: 0,
      );
      expect(getIdempotencyKey(msg), isNull);
    });

    test('retorna null quando nao-string (defesa)', () {
      final msg = Message(
        header: MessageHeader(type: MessageType.executeSchedule, length: 0),
        payload: const <String, dynamic>{'idempotencyKey': 12345},
        checksum: 0,
      );
      expect(getIdempotencyKey(msg), isNull);
    });
  });
}
