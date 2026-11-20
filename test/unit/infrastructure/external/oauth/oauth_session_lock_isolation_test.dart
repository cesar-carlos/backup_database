import 'dart:async';
import 'dart:io';

import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('oauth-lock-isolation-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('should expire queued acquisition without running it later or bypassing the owner', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final owner = OAuthSessionLock(directory: directory).run(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var expiredRan = false;
    var followerRan = false;
    try {
      await expectLater(
        OAuthSessionLock(
          directory: directory,
          acquisitionTimeout: const Duration(milliseconds: 50),
        ).run(() async {
          expiredRan = true;
        }),
        throwsA(isA<TimeoutException>()),
      );
      final follower = OAuthSessionLock(directory: directory).run(() async {
        followerRan = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(followerRan, isFalse);
      release.complete();
      await owner;
      await follower;
      expect(expiredRan, isFalse);
      expect(followerRan, isTrue);
    } finally {
      if (!release.isCompleted) release.complete();
      await owner;
    }
  });

  for (final separateDirectory in [false, true]) {
    test(
      'should not block unrelated credential storage, separate directory=$separateDirectory',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final first =
            OAuthSessionLock(directory: directory, fileName: 'google.lock').run(
              () async {
                entered.complete();
                await release.future;
              },
            );
        await entered.future;
        final other = OAuthSessionLock(
          directory: separateDirectory
              ? Directory(p.join(directory.path, 'other'))
              : directory,
          fileName: separateDirectory ? 'google.lock' : 'dropbox.lock',
        ).run(() async => 'ready');
        try {
          expect(await other.timeout(const Duration(seconds: 2)), 'ready');
        } finally {
          release.complete();
          await first;
          await other;
        }
      },
    );
  }

  test(
    'should keep equivalent paths serialized after an action fails',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var secondEntered = false;
      final first =
          OAuthSessionLock(
            directory: directory,
            fileName: 'google.lock',
          ).run<void>(() async {
            entered.complete();
            await release.future;
            throw StateError('migration failed');
          });
      final failure = expectLater(first, throwsStateError);
      await entered.future;
      final second =
          OAuthSessionLock(
            directory: Directory(p.join(directory.path, '.')),
            fileName: 'google.lock',
          ).run(() async {
            secondEntered = true;
            return 'recovered';
          });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(secondEntered, isFalse);
      release.complete();
      await failure;
      expect(await second, 'recovered');
      expect(
        await OAuthSessionLock(
          directory: directory,
          fileName: 'google.lock',
        ).run(() async => 'restart'),
        'restart',
      );
    },
  );
}
