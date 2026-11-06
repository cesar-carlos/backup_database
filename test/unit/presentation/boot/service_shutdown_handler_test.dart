import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/service/service_shutdown_handler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/presentation/boot/service_bootstrap_log.dart';
import 'package:backup_database/presentation/boot/service_shutdown_callbacks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _ShutdownScheduler extends Mock implements ISchedulerService {}

void main() {
  test('WinSW Ctrl+C subscription is supported and registered once', () async {
    final signals = StreamController<ProcessSignal>.broadcast();
    final watched = <ProcessSignal>[];
    final handler = ServiceShutdownHandler(
      watchSignal: (signal) {
        watched.add(signal);
        return signals.stream;
      },
    );
    final completed = Completer<void>();
    handler.registerCallback((_) async {}, onComplete: completed.complete);
    await handler.initialize();
    await handler.initialize();
    expect(watched, [ProcessSignal.sigint]);
    signals.add(ProcessSignal.sigint);
    await completed.future.timeout(const Duration(seconds: 2));
    await handler.dispose();
    await signals.close();
  }, skip: !Platform.isWindows);
  test(
    'zero shutdown budget still blocks execution before completion',
    () async {
      final handler = ServiceShutdownHandler();
      final scheduler = _ShutdownScheduler();
      final completer = Completer<void>();
      ServiceShutdownCallbacks(
        shutdownCompleter: completer,
        schedulerServiceRef: () => scheduler,
        healthCheckerRef: () => null,
        eventLogRef: () => null,
        log: ServiceBootstrapLog(),
      ).register(handler);
      await handler.shutdown(timeout: Duration.zero);
      verify(scheduler.suspendExecutions).called(1);
      expect(completer.isCompleted, isTrue);
      await handler.dispose();
    },
  );
  test(
    'service shutdown completer resolves even when callback is skipped',
    () async {
      final handler = ServiceShutdownHandler();
      final completer = Completer<void>();
      ServiceShutdownCallbacks(
        shutdownCompleter: completer,
        schedulerServiceRef: () => null,
        healthCheckerRef: () => null,
        eventLogRef: () => null,
        log: ServiceBootstrapLog(),
      ).register(handler);
      await handler.shutdown(timeout: Duration.zero);
      expect(completer.isCompleted, isTrue);
      await handler.dispose();
    },
  );
  test('hung callback is bounded and completion runs exactly once', () async {
    final handler = ServiceShutdownHandler();
    final pending = Completer<void>();
    var completed = 0;
    var skippedRan = false;
    handler.registerCallback((_) async {
      skippedRan = true;
    });
    handler.registerCallback(
      (_) => pending.future,
      onComplete: () {
        completed++;
      },
    );
    await handler
        .shutdown(timeout: const Duration(milliseconds: 20))
        .timeout(const Duration(seconds: 2));
    expect(completed, 1);
    expect(skippedRan, isFalse);
    pending.completeError(StateError('late failure'));
    await Future<void>.delayed(Duration.zero);
    await handler.shutdown();
    expect(completed, 1);
    await handler.dispose();
  });
  test('callback error does not skip other callbacks or completion', () async {
    final handler = ServiceShutdownHandler();
    final events = <String>[];
    handler.registerCallback((_) async {
      events.add('cleanup');
    });
    handler.registerCallback(
      (_) => throw StateError('failure'),
      onComplete: () => events.add('complete'),
    );
    await handler.shutdown();
    expect(events, ['cleanup', 'complete']);
    await handler.dispose();
  });
  test('zero budget still signals completion', () async {
    final handler = ServiceShutdownHandler();
    var completed = false;
    handler.registerCallback(
      (_) async {
        fail('callback must be skipped');
      },
      onComplete: () {
        completed = true;
      },
    );
    await handler.shutdown(timeout: Duration.zero);
    expect(completed, isTrue);
    await handler.dispose();
  });
}
