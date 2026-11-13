import 'dart:convert';
import 'dart:io';

import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows credential lock excludes a separate process', () async {
    final dir = await Directory.systemTemp.createTemp('oauth-lock-process-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/dropbox-session.lock');
    await file.writeAsString('0');
    const script =
        'import sys, msvcrt\n'
        'with open(sys.argv[1], "r+b") as f:\n'
        ' msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)\n'
        ' print("locked", flush=True)\n'
        ' sys.stdin.readline()\n'
        ' f.seek(0)\n'
        ' msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)\n';
    final child = await Process.start('py', [
      '-3',
      '-u',
      '-c',
      script,
      file.path,
    ]);
    addTearDown(child.kill);
    final errors = child.stderr.transform(utf8.decoder).join();
    expect(
      await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first,
      'locked',
    );
    var entered = false;
    final work = OAuthSessionLock(directory: dir).run(() async {
      entered = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(entered, isFalse);
    child.stdin.writeln('release');
    await child.stdin.close();
    expect(await child.exitCode, 0, reason: await errors);
    await work;
    expect(entered, isTrue);
  }, skip: !Platform.isWindows);
}
