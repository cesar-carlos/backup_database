import 'dart:io';

import 'package:backup_database/infrastructure/security/machine_scope_secure_credential_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Legacy extends Mock implements FlutterSecureStorage {}

void main() {
  for (final provider in ['google', 'dropbox']) {
    for (final backupOnly in [false, true]) {
      test(
        'should preserve $provider logout after interrupted replacement, backupOnly=$backupOnly',
        () async {
          final dir = await Directory.systemTemp.createTemp(
            'credential-crash-state-',
          );
          addTearDown(() => dir.delete(recursive: true));
          final legacy = _Legacy();
          final key = '${provider}_oauth_token';
          when(() => legacy.delete(key: key)).thenAnswer((_) async {});
          MachineScopeSecureCredentialService restart() =>
              MachineScopeSecureCredentialService(
                legacyStorage: legacy,
                secretsDirectory: dir,
              );
          (await restart().storeToken(
            key: key,
            tokenData: {'accessToken': 'old', 'refreshToken': 'old-refresh'},
          )).getOrThrow();
          final blob = (await dir.list().toList()).whereType<File>().single;
          final oldBytes = await blob.readAsBytes();
          final marker = <String, dynamic>{
            'signedOut': true,
            'sessionId': 'logout',
          };
          (await restart().storeToken(
            key: key,
            tokenData: marker,
          )).getOrThrow();
          if (backupOnly) {
            await blob.rename('${blob.path}.bak');
          } else {
            await File('${blob.path}.bak').writeAsBytes(oldBytes, flush: true);
          }
          await File('${blob.path}.interrupted.tmp')
              .writeAsBytes(oldBytes, flush: true);
          expect((await restart().getToken(key: key)).getOrThrow(), marker);
          verifyNever(() => legacy.read(key: key));
        },
        skip: !Platform.isWindows,
      );
    }
  }
  for (final provider in ['google', 'dropbox']) {
    for (final invalid in ['truncated-json', '[]', 'null']) {
      test(
        'should not migrate invalid $provider credentials before validation: $invalid',
        () async {
          final dir = await Directory.systemTemp.createTemp(
            'credential-migration-validation-',
          );
          addTearDown(() => dir.delete(recursive: true));
          final legacy = _Legacy();
          final key = '${provider}_oauth_token';
          when(() => legacy.read(key: key)).thenAnswer((_) async => invalid);
          when(() => legacy.delete(key: key)).thenAnswer((_) async {});
          MachineScopeSecureCredentialService restart() =>
              MachineScopeSecureCredentialService(
                legacyStorage: legacy,
                secretsDirectory: dir,
              );
          expect((await restart().getToken(key: key)).isError(), isTrue);
          expect(await dir.list().toList(), isEmpty);
          verifyNever(() => legacy.delete(key: key));
          when(() => legacy.read(key: key)).thenAnswer(
            (_) async => '{"accessToken":"recovered","refreshToken":"refresh"}',
          );
          expect(
            (await restart().getToken(key: key)).getOrThrow()['accessToken'],
            'recovered',
          );
          when(() => legacy.read(key: key))
              .thenThrow(StateError('legacy unavailable'));
          expect(
            (await restart().getToken(key: key)).getOrThrow()['refreshToken'],
            'refresh',
          );
          verify(() => legacy.delete(key: key)).called(1);
        },
        skip: !Platform.isWindows,
      );
    }
  }
  for (final provider in ['google', 'dropbox']) {
    test(
      'should keep $provider logout authoritative over another user legacy credentials',
      () async {
        final dir = await Directory.systemTemp.createTemp('logout-machine-');
        addTearDown(() => dir.delete(recursive: true));
        final key = '${provider}_oauth_token';
        final firstUser = _Legacy();
        when(() => firstUser.delete(key: key))
            .thenThrow(StateError('legacy cleanup failed'));
        final store = MachineScopeSecureCredentialService(
          legacyStorage: firstUser,
          secretsDirectory: dir,
        );
        final marker = <String, dynamic>{
          'signedOut': true,
          'sessionId': 'logout',
        };
        expect(
          (await store.storeToken(key: key, tokenData: marker)).isError(),
          isTrue,
        );
        final otherUser = _Legacy();
        when(() => otherUser.read(key: key)).thenAnswer(
          (_) async => '{"accessToken":"obsolete","refreshToken":"old"}',
        );
        final restarted = MachineScopeSecureCredentialService(
          legacyStorage: otherUser,
          secretsDirectory: dir,
        );
        expect((await restarted.getToken(key: key)).getOrThrow(), marker);
        verifyNever(() => otherUser.read(key: key));
      },
      skip: !Platform.isWindows,
    );
  }
  for (final scenario in [
    'read-backup',
    'read-corrupt',
    'delete-all',
    'delete-all-failure',
  ]) {
    test(
      'should handle all credentials consistently after $scenario',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'credential-all-recovery-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final legacy = _Legacy();
        when(() => legacy.delete(key: any(named: 'key')))
            .thenAnswer((_) async {});
        when(legacy.deleteAll).thenAnswer((_) async {});
        when(legacy.readAll)
            .thenAnswer((_) async => {'google_oauth_token': 'obsolete'});
        when(() => legacy.containsKey(key: any(named: 'key')))
            .thenAnswer((_) async => false);
        final service = MachineScopeSecureCredentialService(
          legacyStorage: legacy,
          secretsDirectory: dir,
        );
        await service.storeToken(
          key: 'google_oauth_token',
          tokenData: {'refreshToken': 'current'},
        );
        final blob = (await dir.list().toList()).whereType<File>().single;
        final backup = await blob.rename('${blob.path}.bak');
        if (scenario == 'read-backup') {
          expect(
            (await service.readAll()).getOrThrow()['google_oauth_token'],
            contains('current'),
          );
        } else if (scenario == 'read-corrupt') {
          await backup.writeAsBytes([1, 2, 3]);
          expect((await service.readAll()).isError(), isTrue);
        } else if (scenario == 'delete-all') {
          final lock = await File('${dir.path}/google-session.lock')
              .writeAsString('lock');
          expect((await service.deleteAll()).isSuccess(), isTrue);
          expect(await backup.exists(), isFalse);
          expect(await lock.exists(), isTrue);
          expect(
            (await service.containsKey(key: 'google_oauth_token')).getOrThrow(),
            isFalse,
          );
        } else {
          when(legacy.deleteAll).thenThrow(StateError('legacy unavailable'));
          expect((await service.deleteAll()).isError(), isTrue);
          expect(
            (await service.getToken(key: 'google_oauth_token'))
                .getOrThrow()['refreshToken'],
            'current',
          );
        }
      },
      skip: !Platform.isWindows,
    );
  }

  for (final scenario in [
    'corrupt-main',
    'corrupt-backup',
    'wrong-key',
    'logout-failure',
  ]) {
    test(
      'should not restore stale legacy credentials after $scenario',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'credential-safe-recovery-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final legacy = _Legacy();
        when(() => legacy.delete(key: any(named: 'key')))
            .thenAnswer((_) async {});
        when(() => legacy.read(key: any(named: 'key')))
            .thenAnswer((_) async => '{"refreshToken":"obsolete"}');
        MachineScopeSecureCredentialService restart() =>
            MachineScopeSecureCredentialService(
              legacyStorage: legacy,
              secretsDirectory: dir,
            );
        final service = restart();
        expect(
          (await service.storeToken(
            key: 'google_oauth_token',
            tokenData: {'refreshToken': 'current'},
          )).isSuccess(),
          isTrue,
        );
        final blob = (await dir.list().toList()).whereType<File>().single;
        if (scenario == 'logout-failure') {
          when(() => legacy.delete(key: any(named: 'key')))
              .thenThrow(StateError('legacy unavailable'));
          expect(
            (await service.deleteToken(key: 'google_oauth_token')).isError(),
            isTrue,
          );
          expect(
            (await restart().getToken(key: 'google_oauth_token'))
                .getOrThrow()['refreshToken'],
            'current',
          );
        } else {
          if (scenario == 'wrong-key') {
            await service.storeToken(
              key: 'other',
              tokenData: {'refreshToken': 'unrelated'},
            );
            final other = (await dir.list().toList())
                .whereType<File>()
                .firstWhere((file) => file.path != blob.path);
            await blob.writeAsBytes(await other.readAsBytes());
          } else {
            final target = scenario == 'corrupt-backup'
                ? await blob.rename('${blob.path}.bak')
                : blob;
            await target.writeAsBytes([1, 2, 3]);
          }
          expect(
            (await restart().getToken(key: 'google_oauth_token')).isError(),
            isTrue,
          );
          expect(
            await File(
              scenario == 'corrupt-backup' ? '${blob.path}.bak' : blob.path,
            ).exists(),
            isTrue,
          );
        }
        verifyNever(() => legacy.read(key: any(named: 'key')));
      },
      skip: !Platform.isWindows,
    );
  }

  for (final action in ['read', 'replace', 'logout']) {
    test(
      'should recover interrupted credential replacement: $action',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'credential-recovery-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final legacy = _Legacy();
        when(() => legacy.delete(key: any(named: 'key')))
            .thenAnswer((_) async {});
        when(() => legacy.containsKey(key: any(named: 'key')))
            .thenAnswer((_) async => false);
        when(() => legacy.read(key: any(named: 'key')))
            .thenAnswer((_) async => null);
        MachineScopeSecureCredentialService restart() =>
            MachineScopeSecureCredentialService(
              legacyStorage: legacy,
              secretsDirectory: dir,
            );
        expect(
          (await restart().storeToken(
            key: 'google_oauth_token',
            tokenData: {'refreshToken': 'previous'},
          )).isSuccess(),
          isTrue,
        );
        final blob = (await dir.list().toList()).whereType<File>().single;
        await blob.rename('${blob.path}.bak');
        final service = restart();
        expect(
          (await service.containsKey(key: 'google_oauth_token')).getOrThrow(),
          isTrue,
        );
        expect(
          (await service.getToken(key: 'google_oauth_token'))
              .getOrThrow()['refreshToken'],
          'previous',
        );
        if (action == 'replace') {
          expect(
            (await service.storeToken(
              key: 'google_oauth_token',
              tokenData: {'refreshToken': 'new'},
            )).isSuccess(),
            isTrue,
          );
          expect(
            (await restart().getToken(key: 'google_oauth_token'))
                .getOrThrow()['refreshToken'],
            'new',
          );
          expect(await File('${blob.path}.bak').exists(), isFalse);
        } else if (action == 'logout') {
          expect(
            (await service.deleteToken(key: 'google_oauth_token')).isSuccess(),
            isTrue,
          );
          expect(
            (await restart().containsKey(key: 'google_oauth_token'))
                .getOrThrow(),
            isFalse,
          );
          expect(
            (await restart().getToken(key: 'google_oauth_token')).isError(),
            isTrue,
          );
        }
      },
      skip: !Platform.isWindows,
    );
  }
}
