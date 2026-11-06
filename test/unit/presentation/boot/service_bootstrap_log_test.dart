import 'dart:async';
import 'dart:io';

import 'package:backup_database/presentation/boot/service_bootstrap_log.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingLog extends ServiceBootstrapLog {
  final pending = Completer<void>();
  @override
  Future<void> flush() => pending.future;
}

void main() {
  test('final diagnostics are on disk before exit', () async {
    final dir = await Directory.systemTemp.createTemp('bootstrap_log_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/boot.log');
    final log = ServiceBootstrapLog(logPath: file.path);
    await log.append('fatal diagnostic');
    var exited = false;
    await log.flushBeforeExit(
      1,
      exitProcess: (code) {
        expect(code, 1);
        expect(file.readAsStringSync(), contains('fatal diagnostic'));
        exited = true;
      },
    );
    expect(exited, isTrue);
  });
  test('exit waits for flush completion', () async {
    final log = _PendingLog();
    final exits = <int>[];
    final done = log.flushBeforeExit(0, exitProcess: exits.add);
    await Future<void>.delayed(Duration.zero);
    expect(exits, isEmpty);
    log.pending.complete();
    await done;
    expect(exits, [0]);
  });
  test('flush timeout still exits with original code', () async {
    final log = _PendingLog();
    final exits = <int>[];
    await log.flushBeforeExit(
      3,
      exitProcess: exits.add,
      timeout: const Duration(milliseconds: 20),
    );
    expect(exits, [3]);
    log.pending.complete();
  });
  test('flush error still exits with original code', () async {
    final log = _PendingLog();
    final exits = <int>[];
    final done = log.flushBeforeExit(2, exitProcess: exits.add);
    log.pending.completeError(StateError('disk unavailable'));
    await done;
    expect(exits, [2]);
  });
}
