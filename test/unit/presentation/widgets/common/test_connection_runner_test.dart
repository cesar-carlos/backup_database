import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/presentation/widgets/common/test_connection_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('testConnectionUserMessage', () {
    test('uses Failure.message when non-empty', () {
      expect(
        testConnectionUserMessage(
          const ServerFailure(message: 'x'),
          fallback: 'fb',
        ),
        'x',
      );
    });

    test('uses fallback when Failure message empty', () {
      expect(
        testConnectionUserMessage(
          const ServerFailure(message: ''),
          fallback: 'fb',
        ),
        'fb',
      );
    });
  });

  group('TestConnectionRunner', () {
    test(
      'returns TestConnectionFailed when validate returns message',
      () async {
        final runner = TestConnectionRunner<int>(
          validate: () => 'missing',
          buildConfig: () => 42,
          runTest: (_) async => const TestConnectionSucceeded(),
        );

        final outcome = await runner.execute();

        expect(outcome, isA<TestConnectionFailed>());
        expect((outcome as TestConnectionFailed).message, 'missing');
      },
    );

    test('returns runTest outcome when validate passes', () async {
      final runner = TestConnectionRunner<String>(
        validate: () => null,
        buildConfig: () => 'cfg',
        runTest: (config) async {
          expect(config, 'cfg');
          return const TestConnectionSucceeded();
        },
      );

      final outcome = await runner.execute();

      expect(outcome, isA<TestConnectionSucceeded>());
    });

    test('propagates failed outcome from runTest', () async {
      final runner = TestConnectionRunner<void>(
        validate: () => null,
        buildConfig: () {},
        runTest: (_) async => const TestConnectionFailed('conn'),
      );

      final outcome = await runner.execute();

      expect(outcome, isA<TestConnectionFailed>());
      expect((outcome as TestConnectionFailed).message, 'conn');
    });

    test('invokes afterValidation only when validate passes', () async {
      var afterCalls = 0;
      final blocked = TestConnectionRunner<int>(
        validate: () => 'blocked',
        buildConfig: () => 1,
        runTest: (_) async => const TestConnectionSucceeded(),
      );
      await blocked.execute(afterValidation: () => afterCalls++);
      expect(afterCalls, 0);

      final ok = TestConnectionRunner<int>(
        validate: () => null,
        buildConfig: () => 2,
        runTest: (_) async => const TestConnectionSucceeded(),
      );
      await ok.execute(afterValidation: () => afterCalls++);
      expect(afterCalls, 1);
    });

    test('TestConnectionSucceeded carries databases', () async {
      final runner = TestConnectionRunner<void>(
        validate: () => null,
        buildConfig: () {},
        runTest: (_) async => const TestConnectionSucceeded(
          databases: <String>['a', 'b'],
        ),
      );
      final outcome = await runner.execute();
      expect(outcome, isA<TestConnectionSucceeded>());
      final s = outcome as TestConnectionSucceeded;
      expect(s.databases, <String>['a', 'b']);
      expect(s.listWarning, isNull);
    });
  });
}
