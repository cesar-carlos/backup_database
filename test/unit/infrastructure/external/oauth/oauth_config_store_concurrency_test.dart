import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_config_store.dart';
import 'package:backup_database/infrastructure/external/oauth/oauth_session_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' hide unit;
import 'package:shared_preferences/shared_preferences.dart';

class _Credentials extends Mock implements ISecureCredentialService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final label in ['Google', 'Dropbox']) {
    for (final committed in [true, false]) {
      test(
        'should recover $label migration after storage error, committed=$committed',
        () async {
          final dir = await Directory.systemTemp.createTemp('oauth-migration-');
          addTearDown(() => dir.delete(recursive: true));
          EncryptionService.initializeWithDeviceKey('oauth-config-test');
          addTearDown(EncryptionService.resetToLegacy);
          final key = '${label.toLowerCase()}_oauth_config';
          final data = <String, dynamic>{'clientId': 'legacy'};
          SharedPreferences.setMockInitialValues({
            key: EncryptionService.encrypt(jsonEncode(data)),
          });
          final credentials = _Credentials();
          Map<String, dynamic>? saved;
          var writes = 0;
          when(() => credentials.containsKey(key: key))
              .thenAnswer((_) async => Success(saved != null));
          when(
            () => credentials.getToken(key: key),
          ).thenAnswer((_) async => Success(Map<String, dynamic>.of(saved!)));
          when(
            () => credentials.storeToken(
              key: key,
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((call) async {
            writes++;
            if (committed || writes > 1) {
              saved = Map<String, dynamic>.of(
                call.namedArguments[#tokenData] as Map<String, dynamic>,
              );
            }
            if (writes == 1) {
              return Failure(Exception('storage response failed'));
            }
            return const Success(unit);
          });
          OAuthConfigStore instance() => OAuthConfigStore(
            credentials,
            storageKey: key,
            label: label,
            sessionLock: OAuthSessionLock(
              directory: dir,
              fileName: '$key.lock',
            ),
          );
          if (committed) {
            expect(await instance().readForUi(), data);
          } else {
            await expectLater(
              instance().readForUi(),
              throwsA(isA<Exception>()),
            );
          }
          expect(await instance().readForUi(), data);
          expect(writes, committed ? 1 : 2);
          expect(await instance().read(), data);
        },
      );
    }
    for (final operation in ['remove', 'write', 'failed-migration']) {
      test(
        'should serialize $label migration with $operation in another instance',
        () async {
          final dir = await Directory.systemTemp.createTemp(
            'oauth-config-lock-',
          );
          addTearDown(() => dir.delete(recursive: true));
          EncryptionService.initializeWithDeviceKey('oauth-config-test');
          addTearDown(EncryptionService.resetToLegacy);
          final key = '${label.toLowerCase()}_oauth_config';
          SharedPreferences.setMockInitialValues({
            key: EncryptionService.encrypt(jsonEncode({'clientId': 'legacy'})),
          });
          final credentials = _Credentials();
          Map<String, dynamic>? saved;
          final entered = Completer<void>();
          final release = Completer<void>();
          var writes = 0;
          when(() => credentials.containsKey(key: key))
              .thenAnswer((_) async => Success(saved != null));
          when(
            () => credentials.getToken(key: key),
          ).thenAnswer((_) async => Success(Map<String, dynamic>.of(saved!)));
          when(
            () => credentials.storeToken(
              key: key,
              tokenData: any(named: 'tokenData'),
            ),
          ).thenAnswer((call) async {
            if (writes++ == 0) {
              entered.complete();
              await release.future;
              if (operation == 'failed-migration') {
                return Failure(Exception('disk unavailable'));
              }
            }
            saved = Map<String, dynamic>.of(
              call.namedArguments[#tokenData] as Map<String, dynamic>,
            );
            return const Success(unit);
          });
          OAuthConfigStore instance() => OAuthConfigStore(
            credentials,
            storageKey: key,
            label: label,
            sessionLock: OAuthSessionLock(
              directory: dir,
              fileName: '$key.lock',
            ),
          );
          final migration = instance().readForUi();
          final migrationExpectation = operation == 'failed-migration'
              ? expectLater(migration, throwsA(isA<Exception>()))
              : migration;
          await entered.future;
          final other = operation == 'write'
              ? instance().write({'clientId': 'new'})
              : instance().remove();
          release.complete();
          await migrationExpectation;
          await other;
          final restored = await instance().readForUi();
          if (operation == 'write') {
            expect(restored!['clientId'], 'new');
          } else {
            expect(restored, isNull);
            expect(saved, {'removed': true});
          }
        },
      );
    }
  }
}
