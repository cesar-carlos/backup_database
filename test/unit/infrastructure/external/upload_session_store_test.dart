import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/upload_session_store.dart';
import 'package:backup_database/infrastructure/security/machine_scope_secure_credential_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _Storage extends Mock implements ISecureCredentialService {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));
  late Directory temp;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('upload_checkpoint_');
  });
  tearDown(() => temp.delete(recursive: true));
  UploadSessionStore restart() => UploadSessionStore(
    directory: temp,
    credentials: MachineScopeSecureCredentialService(secretsDirectory: temp),
  );

  test(
    'should reject an old checkpoint handle after a newer attempt commits',
    () async {
      late UploadSessionCheckpoint old;
      await restart().run(['lifetime'], (checkpoint) async {
        old = checkpoint;
        await checkpoint.save({'session': 'old'});
      });
      await restart().run([
        'lifetime',
      ], (checkpoint) => checkpoint.save({'session': 'new'}));
      await expectLater(
        old.save({'session': 'late'}),
        throwsA(isA<StateError>()),
      );
      await expectLater(old.clear(), throwsA(isA<StateError>()));
      await expectLater(old.read(), throwsA(isA<StateError>()));
      expect(
        await restart().run(['lifetime'], (checkpoint) => checkpoint.read()),
        {'session': 'new'},
      );
    },
  );

  for (final mode in ['return', 'throw', 'timeout']) {
    test(
      'should retain lock for pending writes when callback ends: $mode',
      () async {
        final storage = _Storage();
        final entered = Completer<void>();
        final pending = Completer<rd.Result<Unit>>();
        Map<String, dynamic>? disk;
        when(
          () => storage.storeToken(
            key: any(named: 'key'),
            tokenData: any(named: 'tokenData'),
          ),
        ).thenAnswer((call) async {
          entered.complete();
          final result = await pending.future;
          disk = call.namedArguments[#tokenData] as Map<String, dynamic>;
          return result;
        });
        when(() => storage.containsKey(key: any(named: 'key')))
            .thenAnswer((_) async => rd.Success(disk != null));
        when(() => storage.getToken(key: any(named: 'key')))
            .thenAnswer((_) async => rd.Success(disk!));
        final store = UploadSessionStore(
          credentials: storage,
          directory: temp,
          storageTimeout: mode == 'timeout'
              ? const Duration(milliseconds: 100)
              : const Duration(seconds: 10),
        );
        late Future<void> write;
        final first = store.run(['pending'], (checkpoint) async {
          write = checkpoint.save({'session': 'late'});
          unawaited(
            write.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          );
          if (mode == 'throw') throw StateError('callback failed');
        });
        final observed = mode == 'return'
            ? first
            : expectLater(
                first,
                throwsA(
                  mode == 'timeout'
                      ? isA<TimeoutException>()
                      : isA<StateError>(),
                ),
              );
        await entered.future;
        if (mode == 'timeout') await observed;
        var nextEntered = false;
        final next = store.run(['pending'], (checkpoint) async {
          nextEntered = true;
          return checkpoint.read();
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(nextEntered, isFalse);
        pending.complete(const rd.Success(unit));
        await observed;
        if (mode == 'timeout') {
          await expectLater(write, throwsA(isA<TimeoutException>()));
        } else {
          await write;
        }
        expect(await next, {'session': 'late'});
      },
    );
  }

  for (final clearing in [false, true]) {
    for (final phase in ['temporary', 'backup-only', 'replacement']) {
      test(
        'should recover interrupted disk replacement phase=$phase clearing=$clearing',
        () async {
          final identity = <Object>['drive', 'recovery'];
          await restart().run(
            identity,
            (checkpoint) => checkpoint.save({'session': 'previous'}),
          );
          final file = (await temp.list().toList())
              .whereType<File>()
              .singleWhere((file) => file.path.endsWith('.bdsecret'));
          final previous = await file.readAsBytes();
          await restart().run(
            identity,
            (checkpoint) => clearing
                ? checkpoint.clear()
                : checkpoint.save({'session': 'next'}),
          );
          final replacement = await file.readAsBytes();
          if (phase == 'replacement') {
            await File('${file.path}.bak').writeAsBytes(previous, flush: true);
          } else {
            await File('${file.path}.interrupted.tmp')
                .writeAsBytes(replacement, flush: true);
            if (phase == 'backup-only') {
              await File('${file.path}.bak')
                  .writeAsBytes(previous, flush: true);
              await file.delete();
            } else {
              await file.writeAsBytes(previous, flush: true);
            }
          }
          final restored = await restart().run(
            identity,
            (checkpoint) => checkpoint.read(),
          );
          expect(
            restored,
            phase == 'replacement'
                ? (clearing ? null : {'session': 'next'})
                : {'session': 'previous'},
          );
          await restart().run(
            identity,
            (checkpoint) => checkpoint.save({'session': 'retry'}),
          );
          expect(
            await restart().run(identity, (checkpoint) => checkpoint.read()),
            {'session': 'retry'},
          );
        },
        skip: !Platform.isWindows,
      );
    }
  }

  for (final timeout in [false, true]) {
    for (final clear in [false, true]) {
      test(
        'should retain lock until late storage settles timeout=$timeout clear=$clear',
        () async {
          final storage = _Storage();
          final entered = Completer<void>();
          final pending = Completer<rd.Result<Unit>>();
          Map<String, dynamic>? written;
          when(
            () => storage.storeToken(
              key: any(named: 'key'),
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((call) {
            written = call.namedArguments[#tokenData] as Map<String, dynamic>;
            entered.complete();
            return pending.future;
          });
          when(() => storage.containsKey(key: any(named: 'key')))
              .thenAnswer((_) async => const rd.Success(true));
          when(() => storage.getToken(key: any(named: 'key')))
              .thenAnswer((_) async => rd.Success(written!));
          var cancelled = false;
          var continued = false;
          final store = UploadSessionStore(
            credentials: storage,
            directory: temp,
            storageTimeout: timeout
                ? const Duration(milliseconds: 100)
                : const Duration(seconds: 10),
          );
          final identity = <Object>['drive', 'pending'];
          final first = store.run(identity, (checkpoint) async {
            if (clear) {
              await checkpoint.clear();
            } else {
              await checkpoint.save({'session': 'late'});
            }
            continued = true;
          }, isCancelled: () => cancelled);
          await entered.future;
          cancelled = !timeout;
          await expectLater(
            first,
            throwsA(
              timeout
                  ? isA<TimeoutException>()
                  : isA<UploadCancelledException>(),
            ),
          );
          cancelled = false;
          var nextEntered = false;
          final next = store.run(identity, (checkpoint) async {
            nextEntered = true;
            return checkpoint.read();
          });
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(nextEntered, isFalse);
          pending.complete(const rd.Success(unit));
          expect(await next, clear ? null : {'session': 'late'});
          expect(continued, isFalse);
        },
      );
    }
  }

  test(
    'should never run a cancelled queued attempt after cancellation is reset',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final first = restart().run(['queue'], (_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var cancelled = false;
      var ran = false;
      final queued = restart().run(['queue'], (_) async {
        ran = true;
      }, isCancelled: () => cancelled);
      cancelled = true;
      await expectLater(queued, throwsA(isA<UploadCancelledException>()));
      cancelled = false;
      release.complete();
      await first;
      await restart().run(['queue'], (_) async {});
      expect(ran, isFalse);
    },
  );

  test(
    'should recover checkpoint after the native lock owner process exits',
    () async {
      final identity = <Object>[
        'drive',
        'account',
        'folder',
        'file',
        4,
        'hash',
      ];
      await restart().run(
        identity,
        (checkpoint) => checkpoint.save({'session': 'durable'}),
      );
      final lock = (await temp.list().toList()).whereType<File>().singleWhere(
        (file) => file.path.endsWith('.lock'),
      );
      const script =
          'import sys, msvcrt\n'
          'with open(sys.argv[1], "r+b") as f:\n'
          ' msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)\n'
          ' print("locked", flush=True)\n'
          ' sys.stdin.readline()\n';
      final child = await Process.start('py', [
        '-3',
        '-u',
        '-c',
        script,
        lock.path,
      ]);
      addTearDown(child.kill);
      final errors = child.stderr.transform(utf8.decoder).join();
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 10)),
        'locked',
      );
      var entered = false;
      final work = restart().run(identity, (checkpoint) async {
        entered = true;
        return checkpoint.read();
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(entered, isFalse);
      child.kill();
      await child.exitCode;
      await errors;
      expect(await work.timeout(const Duration(seconds: 5)), {
        'session': 'durable',
      });
      expect(entered, isTrue);
    },
    skip: !Platform.isWindows,
  );

  for (final clear in [false, true]) {
    for (final committed in [false, true]) {
      test(
        'should reconcile failed checkpoint write clear=$clear committed=$committed',
        () async {
          final storage = _Storage();
          var disk = <String, dynamic>{
            'version': 1,
            'state': {'session': 'previous'},
          };
          when(
            () => storage.storeToken(
              key: any(named: 'key'),
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((call) async {
            if (committed) {
              disk = call.namedArguments[#tokenData] as Map<String, dynamic>;
            }
            return const rd.Failure(StorageFailure(message: 'cleanup failed'));
          });
          when(() => storage.getToken(key: any(named: 'key')))
              .thenAnswer((_) async => rd.Success(disk));
          final work = UploadSessionStore(credentials: storage, directory: temp)
              .run(
                ['checkpoint'],
                (checkpoint) => clear
                    ? checkpoint.clear()
                    : checkpoint.save({'session': 'new'}),
              );
          if (committed) {
            await work;
            expect(
              disk,
              clear
                  ? {'version': 1, 'cleared': true}
                  : {
                      'version': 1,
                      'state': {'session': 'new'},
                    },
            );
          } else {
            await expectLater(work, throwsA(isA<StorageFailure>()));
          }
        },
      );
    }
  }

  test(
    'should serialize different contents targeting the same remote resource',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final first = restart().run(['drive', 'hash-a'], (checkpoint) async {
        entered.complete();
        await release.future;
        await checkpoint.save({'session': 'a'});
      }, resourceIdentity: ['drive', 'account', 'folder', 'name']);
      await entered.future;
      var secondEntered = false;
      final second = restart().run(['drive', 'hash-b'], (checkpoint) async {
        secondEntered = true;
        expect(await checkpoint.read(), isNull);
      }, resourceIdentity: ['drive', 'account', 'folder', 'name']);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(secondEntered, isFalse);
      release.complete();
      await first;
      await second;
    },
  );

  test(
    'should reject an inconsistent cleared checkpoint instead of restarting',
    () async {
      final storage = _Storage();
      when(() => storage.containsKey(key: any(named: 'key')))
          .thenAnswer((_) async => const rd.Success(true));
      when(() => storage.getToken(key: any(named: 'key'))).thenAnswer(
        (_) async => const rd.Success({
          'version': 1,
          'cleared': true,
          'state': {'session': 'previous'},
        }),
      );
      await expectLater(
        UploadSessionStore(
          credentials: storage,
          directory: temp,
        ).run(['invalid'], (checkpoint) => checkpoint.read()),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'should isolate checkpoints by provider account destination and content',
    () async {
      final identity = <Object>[
        'drive',
        'account',
        'folder',
        'file',
        4,
        'hash',
      ];
      await restart().run(
        identity,
        (checkpoint) => checkpoint.save({'session': 'secret'}),
      );
      for (var i = 0; i < identity.length; i++) {
        final other = [...identity]..[i] = 'different';
        expect(
          await restart().run(other, (checkpoint) => checkpoint.read()),
          isNull,
        );
      }
      expect(await restart().run(identity, (checkpoint) => checkpoint.read()), {
        'session': 'secret',
      });
      await restart().run(identity, (checkpoint) => checkpoint.clear());
      expect(
        await restart().run(identity, (checkpoint) => checkpoint.read()),
        isNull,
      );
    },
  );

  test(
    'should serialize fresh store instances until pending write completes',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final identity = <Object>['dropbox', 'account', '/file', 4, 'hash'];
      final first = restart().run(identity, (checkpoint) async {
        entered.complete();
        await release.future;
        await checkpoint.save({'session': 'committed'});
      });
      await entered.future;
      var secondEntered = false;
      final second = restart().run(identity, (checkpoint) async {
        secondEntered = true;
        return checkpoint.read();
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(secondEntered, isFalse);
      release.complete();
      await first;
      expect(await second, {'session': 'committed'});
    },
  );

  test('should fail closed on unreadable checkpoint after restart', () async {
    final identity = <Object>['drive', 'account', 'folder', 'file', 4, 'hash'];
    await restart().run(
      identity,
      (checkpoint) => checkpoint.save({'uri': 'secret'}),
    );
    final blob = (await temp.list().toList()).whereType<File>().singleWhere(
      (file) => file.path.endsWith('.bdsecret'),
    );
    await blob.writeAsBytes([1, 2, 3], flush: true);
    await expectLater(
      restart().run(identity, (checkpoint) => checkpoint.read()),
      throwsA(anything),
    );
  }, skip: !Platform.isWindows);
}
