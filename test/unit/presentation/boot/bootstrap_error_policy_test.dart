import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void _ignoreLog(String _) {}

void _ignoreLogWithError(
  String _, [
  Object? ignoredError,
  StackTrace? ignoredStackTrace,
]) {}

void main() {
  group('BootstrapErrorPolicy.handleUnhandledUiError', () {
    test('filters known Flutter physicalKey already pressed error', () {
      final debugLogs = <String>[];
      final errorLogs = <String>[];
      final policy = BootstrapErrorPolicy(
        logDebug: debugLogs.add,
        logError: (message, [error, stackTrace]) {
          errorLogs.add(message);
        },
        cleanupApp: () async {},
        exitProcess: (_) {},
      );

      policy.handleUnhandledUiError(
        Exception(
          'A KeyDownEvent was dispatched for a key whose physicalKey is '
          'already pressed.',
        ),
        StackTrace.current,
      );

      expect(debugLogs, hasLength(1));
      expect(debugLogs.first, contains('physicalKey is already pressed'));
      expect(errorLogs, isEmpty);
    });

    test('routes generic errors to logError', () {
      final debugLogs = <String>[];
      final errorLogs = <String>[];
      final policy = BootstrapErrorPolicy(
        logDebug: debugLogs.add,
        logError: (message, [error, stackTrace]) {
          errorLogs.add(message);
        },
        cleanupApp: () async {},
        exitProcess: (_) {},
      );

      policy.handleUnhandledUiError(
        StateError('boom'),
        StackTrace.current,
      );

      expect(errorLogs, hasLength(1));
      expect(errorLogs.first, equals('Erro nao tratado na UI'));
      expect(debugLogs, isEmpty);
    });
  });

  group('BootstrapErrorPolicy.handleFatalUiBootstrapFailure', () {
    test(
      'logs error, runs cleanup and exits with bootstrap failure code',
      () async {
        final errorLogs = <String>[];
        var cleanupRan = false;
        final exitCodes = <int>[];
        final policy = BootstrapErrorPolicy(
          logDebug: _ignoreLog,
          logError: (message, [error, stackTrace]) {
            errorLogs.add(message);
          },
          cleanupApp: () async {
            cleanupRan = true;
          },
          exitProcess: exitCodes.add,
        );

        await policy.handleFatalUiBootstrapFailure(
          StateError('boom'),
          StackTrace.current,
        );

        expect(errorLogs, contains('Erro fatal na inicializacao'));
        expect(cleanupRan, isTrue);
        expect(exitCodes, equals(<int>[1]));
      },
    );

    test('still calls exit when cleanup throws', () async {
      final exitCodes = <int>[];
      final policy = BootstrapErrorPolicy(
        logDebug: _ignoreLog,
        logError: _ignoreLogWithError,
        cleanupApp: () async => throw StateError('cleanup failed'),
        exitProcess: exitCodes.add,
      );

      await expectLater(
        () => policy.handleFatalUiBootstrapFailure(
          StateError('boom'),
          StackTrace.current,
        ),
        throwsStateError,
      );
      expect(exitCodes, isEmpty);
    });
  });
}
