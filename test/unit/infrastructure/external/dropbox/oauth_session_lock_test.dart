import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Handle extends Mock implements RandomAccessFile {}

void main() {
  for (final actionFails in [false, true]) {
    test(
      'should recover uncertain release without hiding action error: $actionFails',
      () async {
        final dir = await Directory.systemTemp.createTemp('lock-release-');
        addTearDown(() => dir.delete(recursive: true));
        final handle = _Handle();
        when(() => handle.lock(FileLock.exclusive, 0, 1))
            .thenAnswer((_) async => handle);
        when(() => handle.unlock(0, 1))
            .thenThrow(const FileSystemException('unlock failed'));
        var closes = 0;
        when(handle.close).thenAnswer((_) async {
          if (++closes <= 2) throw const FileSystemException('close failed');
        });
        var opens = 0;
        final lock = OAuthSessionLock(
          directory: dir,
          openFile: (_) async {
            opens++;
            return handle;
          },
        );
        final original = StateError('operation failed');
        await expectLater(
          lock.run(() async {
            if (actionFails) throw original;
            return 'saved';
          }),
          throwsA(actionFails ? same(original) : isA<FileSystemException>()),
        );
        var entered = false;
        await expectLater(
          lock.run(() async {
            entered = true;
          }),
          throwsA(isA<FileSystemException>()),
        );
        expect(entered, isFalse);
        expect(opens, 1);
        when(() => handle.unlock(0, 1)).thenAnswer((_) async => handle);
        expect(await lock.run(() async => 'recovered'), 'recovered');
        expect(opens, 2);
      },
    );
  }

  test('should accept successful close when explicit unlock fails', () async {
    final dir = await Directory.systemTemp.createTemp('lock-close-');
    addTearDown(() => dir.delete(recursive: true));
    final handle = _Handle();
    when(() => handle.lock(FileLock.exclusive, 0, 1))
        .thenAnswer((_) async => handle);
    when(() => handle.unlock(0, 1))
        .thenThrow(const FileSystemException('unlock failed'));
    when(handle.close).thenAnswer((_) async {});
    final lock = OAuthSessionLock(
      directory: dir,
      openFile: (_) async => handle,
    );
    expect(await lock.run(() async => 1), 1);
    expect(await lock.run(() async => 2), 2);
    verify(handle.close).called(2);
  });

  test(
    'should keep queued attempts out until delayed close finishes',
    () async {
      final dir = await Directory.systemTemp.createTemp('lock-pending-close-');
      addTearDown(() => dir.delete(recursive: true));
      final handle = _Handle();
      final closing = Completer<void>();
      final release = Completer<void>();
      when(() => handle.lock(FileLock.exclusive, 0, 1))
          .thenAnswer((_) async => handle);
      when(() => handle.unlock(0, 1)).thenAnswer((_) async => handle);
      var closes = 0;
      when(handle.close).thenAnswer((_) async {
        if (++closes == 1) {
          closing.complete();
          await release.future;
        }
      });
      final lock = OAuthSessionLock(
        directory: dir,
        openFile: (_) async => handle,
      );
      final first = lock.run(() async => 'first');
      await closing.future;
      var expiredEntered = false;
      await expectLater(
        OAuthSessionLock(
          directory: dir,
          acquisitionTimeout: const Duration(milliseconds: 100),
          openFile: (_) async => handle,
        ).run(() async {
          expiredEntered = true;
        }),
        throwsA(isA<TimeoutException>()),
      );
      var entered = false;
      final second = lock.run(() async {
        entered = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(entered, isFalse);
      release.complete();
      expect(await first, 'first');
      await second;
      expect(entered, isTrue);
      expect(expiredEntered, isFalse);
    },
  );
  for (final fileName in ['dropbox-session.lock', 'google-session.lock']) {
    test(
      'Windows credential lock $fileName excludes a separate process',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'oauth-lock-process-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/$fileName');
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
        var expiredEntered = false;
        await expectLater(
          OAuthSessionLock(
            directory: dir,
            fileName: fileName,
            acquisitionTimeout: const Duration(milliseconds: 100),
          ).run(() async {
            expiredEntered = true;
          }),
          throwsA(isA<TimeoutException>()),
        );
        final work = OAuthSessionLock(directory: dir, fileName: fileName).run(
          () async {
            entered = true;
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(entered, isFalse);
        child.stdin.writeln('release');
        await child.stdin.close();
        expect(await child.exitCode, 0, reason: await errors);
        await work;
        expect(entered, isTrue);
        expect(expiredEntered, isFalse);
      },
      skip: !Platform.isWindows,
    );
  }
}
