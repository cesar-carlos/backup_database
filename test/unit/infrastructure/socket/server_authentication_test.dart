import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_credential_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/server_authentication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockServerCredentialDao extends Mock implements ServerCredentialDao {}

void main() {
  late ServerAuthentication authentication;
  late MockServerCredentialDao mockDao;

  const serverId = 'test-server-123';
  const password = 'test-password';
  final passwordHash = PasswordHasher.hash(password, serverId);

  Message createAuthRequestMessage({
    required String serverId,
    required String passwordHash,
  }) {
    return Message(
      header: MessageHeader(
        type: MessageType.authRequest,
        length: 0,
      ),
      payload: <String, dynamic>{
        'serverId': serverId,
        'passwordHash': passwordHash,
      },
      checksum: 0,
    );
  }

  setUp(() {
    mockDao = MockServerCredentialDao();
    authentication = ServerAuthentication(mockDao);
  });

  group('ServerAuthentication', () {
    test('should return true when credential matches passwordHash', () async {
      final credential = ServerCredentialsTableData(
        id: '1',
        serverId: serverId,
        passwordHash: passwordHash,
        name: 'Test',
        isActive: true,
        createdAt: DateTime.now(),
      );
      when(() => mockDao.getByServerId(serverId))
          .thenAnswer((_) async => credential);

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: passwordHash,
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result, isTrue);
      verify(() => mockDao.getByServerId(serverId)).called(1);
    });

    test('should return false when passwordHash does not match', () async {
      final credential = ServerCredentialsTableData(
        id: '1',
        serverId: serverId,
        passwordHash: passwordHash,
        name: 'Test',
        isActive: true,
        createdAt: DateTime.now(),
      );
      when(() => mockDao.getByServerId(serverId))
          .thenAnswer((_) async => credential);

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: 'wrong-hash',
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result, isFalse);
    });

    test('should return false when no credential for serverId', () async {
      when(() => mockDao.getByServerId(serverId)).thenAnswer((_) async => null);

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: passwordHash,
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result, isFalse);
    });

    test('should return false when credential is inactive', () async {
      final credential = ServerCredentialsTableData(
        id: '1',
        serverId: serverId,
        passwordHash: passwordHash,
        name: 'Test',
        isActive: false,
        createdAt: DateTime.now(),
      );
      when(() => mockDao.getByServerId(serverId))
          .thenAnswer((_) async => credential);

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: passwordHash,
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result, isFalse);
    });

    test('should return false when serverId is empty in payload', () async {
      final message = Message(
        header: MessageHeader(
          type: MessageType.authRequest,
          length: 0,
        ),
        payload: <String, dynamic>{
          'serverId': '',
          'passwordHash': passwordHash,
        },
        checksum: 0,
      );

      final result = await authentication.validateAuthRequest(message);

      expect(result, isFalse);
      verifyNever(() => mockDao.getByServerId(any()));
    });
  });
}
