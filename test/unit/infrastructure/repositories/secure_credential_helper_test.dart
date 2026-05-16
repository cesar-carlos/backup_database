import 'package:backup_database/core/constants/secure_credential_keys.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/repositories/secure_credential_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockSecureCredentialService extends Mock
    implements ISecureCredentialService {}

void main() {
  late _MockSecureCredentialService mockService;
  late SecureCredentialHelper helper;

  setUp(() {
    mockService = _MockSecureCredentialService();
    helper = SecureCredentialHelper(mockService);
  });

  group('SecureCredentialKeys', () {
    test('builds stable keys per engine', () {
      expect(
        SecureCredentialKeys.sqlServerPasswordKey('abc'),
        '${SecureCredentialKeys.sqlServerPasswordPrefix}abc',
      );
      expect(
        SecureCredentialKeys.sybasePasswordKey('abc'),
        '${SecureCredentialKeys.sybasePasswordPrefix}abc',
      );
      expect(
        SecureCredentialKeys.postgresPasswordKey('abc'),
        '${SecureCredentialKeys.postgresPasswordPrefix}abc',
      );
    });
  });

  group('SecureCredentialHelper', () {
    test(
      'storePasswordOrThrow propagates service exception on error',
      () async {
        final ex = Exception('vault full');
        when(
          () => mockService.storePassword(
            key: any(named: 'key'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => rd.Failure(ex));

        await expectLater(
          helper.storePasswordOrThrow(key: 'k', password: 'p'),
          throwsA(ex),
        );
      },
    );

    test('storePasswordOrThrow completes when service succeeds', () async {
      when(
        () => mockService.storePassword(
          key: any(named: 'key'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => const rd.Success(unit));

      await helper.storePasswordOrThrow(key: 'k', password: 'secret');

      verify(
        () => mockService.storePassword(key: 'k', password: 'secret'),
      ).called(1);
    });

    test('readPasswordOrEmpty returns empty on getPassword failure', () async {
      when(
        () => mockService.getPassword(key: any(named: 'key')),
      ).thenAnswer((_) async => rd.Failure(Exception('missing')));

      final out = await helper.readPasswordOrEmpty('k');
      expect(out, '');
    });

    test('readPasswordOrEmpty returns value on success', () async {
      when(
        () => mockService.getPassword(key: any(named: 'key')),
      ).thenAnswer((_) async => const rd.Success('pwd'));

      final out = await helper.readPasswordOrEmpty('k');
      expect(out, 'pwd');
    });

    test('deletePassword forwards to service', () async {
      when(
        () => mockService.deletePassword(key: any(named: 'key')),
      ).thenAnswer((_) async => const rd.Success(unit));

      await helper.deletePassword('k');

      verify(() => mockService.deletePassword(key: 'k')).called(1);
    });
  });
}
