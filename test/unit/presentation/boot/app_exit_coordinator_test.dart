import 'dart:async';

import 'package:backup_database/presentation/boot/app_exit_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reenterFromStart in [true, false]) {
    test(
      'reentrant exit from ${reenterFromStart ? 'onStart' : 'cleanup'} is shared',
      () async {
        var starts = 0;
        var cleanups = 0;
        var exits = 0;
        Future<void>? nested;
        late AppExitCoordinator coordinator;
        coordinator = AppExitCoordinator(
          onStart: () {
            starts++;
            expect(coordinator.isExiting, isTrue);
            if (reenterFromStart && starts == 1) {
              nested = coordinator.requestExit();
            }
          },
          cleanup: () async {
            cleanups++;
            if (!reenterFromStart && cleanups == 1) {
              nested = coordinator.requestExit();
            }
          },
          exitProcess: (_) => exits++,
        );
        final exit = coordinator.requestExit();
        expect(identical(exit, nested), isTrue);
        await exit;
        expect([starts, cleanups, exits], [1, 1, 1]);
      },
    );
  }
  test('X and tray requests share one cleanup and one exit', () async {
    final done = Completer<void>();
    final events = <String>[];
    final coordinator = AppExitCoordinator(
      onStart: () => events.add('block_ui'),
      cleanup: () async {
        events.add('cleanup');
        await done.future;
      },
      exitProcess: (code) => events.add('exit:$code'),
    );
    final x = coordinator.requestExit();
    final tray = coordinator.requestExit();
    expect(identical(x, tray), isTrue);
    expect(coordinator.isExiting, isTrue);
    expect(events, ['block_ui', 'cleanup']);
    done.complete();
    await Future.wait([x, tray]);
    await coordinator.requestExit();
    expect(events, ['block_ui', 'cleanup', 'exit:0']);
  });

  for (final hangs in [false, true]) {
    test('exits even if cleanup ${hangs ? 'hangs' : 'throws'}', () async {
      final pending = Completer<void>();
      final exits = <int>[];
      final coordinator = AppExitCoordinator(
        onStart: () {},
        cleanup: () =>
            hangs ? pending.future : Future.error(StateError('failed')),
        exitProcess: exits.add,
        timeout: const Duration(milliseconds: 10),
      );
      await coordinator.requestExit();
      expect(exits, [0]);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(exits, [0]);
    });
  }
}
