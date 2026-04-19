import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_credential_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/server_authentication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class MockServerCredentialDao extends Mock implements ServerCredentialDao {}

class MockLicenseValidationService extends Mock
    implements ILicenseValidationService {}

void main() {
  late ServerAuthentication authentication;
  late MockServerCredentialDao mockDao;
  late MockLicenseValidationService mockLicenseValidationService;

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
    mockLicenseValidationService = MockLicenseValidationService();
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
      when(
        () => mockDao.getByServerId(serverId),
      ).thenAnswer((_) async => credential);

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: passwordHash,
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result.isValid, isTrue);
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
      when(
        () => mockDao.getByServerId(serverId),
      ).thenAnswer((_) async => credential);

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: 'wrong-hash',
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result.isValid, isFalse);
    });

    test('should return false when no credential for serverId', () async {
      when(() => mockDao.getByServerId(serverId)).thenAnswer((_) async => null);

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: passwordHash,
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result.isValid, isFalse);
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
      when(
        () => mockDao.getByServerId(serverId),
      ).thenAnswer((_) async => credential);

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: passwordHash,
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result.isValid, isFalse);
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

      expect(result.isValid, isFalse);
      verifyNever(() => mockDao.getByServerId(any()));
    });

    test(
      'should return false when serverConnection feature denied by license',
      () async {
        // F0.4: este teste antes mockava `remoteControl`, mas o codigo
        // real consulta `serverConnection`. Mocktail jogava
        // MissingStubError, capturado pelo `catch` generico, retornando
        // licenseDenied por COINCIDENCIA — falso positivo. Agora o stub
        // bate com a feature exata.
        authentication = ServerAuthentication(
          mockDao,
          licenseValidationService: mockLicenseValidationService,
        );
        when(
          () => mockLicenseValidationService.isFeatureAllowed(
            LicenseFeatures.serverConnection,
          ),
        ).thenAnswer((_) async => const rd.Success(false));

        final message = createAuthRequestMessage(
          serverId: serverId,
          passwordHash: passwordHash,
        );
        final result = await authentication.validateAuthRequest(message);

        expect(result.isValid, isFalse);
        expect(result.errorCode, ErrorCode.licenseDenied);
        verifyNever(() => mockDao.getByServerId(any()));
        verify(
          () => mockLicenseValidationService.isFeatureAllowed(
            LicenseFeatures.serverConnection,
          ),
        ).called(1);
      },
    );

    test('should return false when license validation throws Failure', () async {
      authentication = ServerAuthentication(
        mockDao,
        licenseValidationService: mockLicenseValidationService,
      );
      when(
        () => mockLicenseValidationService.isFeatureAllowed(
          LicenseFeatures.serverConnection,
        ),
      ).thenAnswer((_) async => rd.Failure(Exception('license error')));

      final message = createAuthRequestMessage(
        serverId: serverId,
        passwordHash: passwordHash,
      );
      final result = await authentication.validateAuthRequest(message);

      expect(result.isValid, isFalse);
      expect(result.errorCode, ErrorCode.licenseDenied);
      verifyNever(() => mockDao.getByServerId(any()));
    });

    test(
      'should return false when license service throws synchronously',
      () async {
        // F0.4: cobre o ramo `catch (e, st)` em
        // ServerAuthentication.validateAuthRequest. Antes desse teste o
        // ramo era exercitado apenas por coincidencia (MissingStubError).
        authentication = ServerAuthentication(
          mockDao,
          licenseValidationService: mockLicenseValidationService,
        );
        when(
          () => mockLicenseValidationService.isFeatureAllowed(
            LicenseFeatures.serverConnection,
          ),
        ).thenThrow(StateError('license subsystem corrompido'));

        final message = createAuthRequestMessage(
          serverId: serverId,
          passwordHash: passwordHash,
        );
        final result = await authentication.validateAuthRequest(message);

        expect(result.isValid, isFalse);
        expect(result.errorCode, ErrorCode.licenseDenied);
        verifyNever(() => mockDao.getByServerId(any()));
      },
    );

    test(
      'should return false when passwordHash is empty (defesa F0.4)',
      () async {
        // Antes coberto apenas para serverId — o `||` na verificacao
        // protege ambos, mas teste explicito ancora o comportamento.
        final message = Message(
          header: MessageHeader(
            type: MessageType.authRequest,
            length: 0,
          ),
          payload: <String, dynamic>{
            'serverId': serverId,
            'passwordHash': '',
          },
          checksum: 0,
        );
        final result = await authentication.validateAuthRequest(message);
        expect(result.isValid, isFalse);
        expect(result.errorCode, ErrorCode.invalidRequest);
        verifyNever(() => mockDao.getByServerId(any()));
      },
    );

    test(
      'should return false when payload field has wrong type (defesa F0.4)',
      () async {
        // Cliente buggy / peer hostil envia int em vez de string.
        // Cast `as String?` retorna null → cai no ramo de invalidRequest.
        final message = Message(
          header: MessageHeader(
            type: MessageType.authRequest,
            length: 0,
          ),
          payload: const <String, dynamic>{
            'serverId': 12345,
            'passwordHash': true,
          },
          checksum: 0,
        );
        final result = await authentication.validateAuthRequest(message);
        expect(result.isValid, isFalse);
        expect(result.errorCode, ErrorCode.invalidRequest);
        verifyNever(() => mockDao.getByServerId(any()));
      },
    );

    test(
      'should reject non-authRequest message type (defesa F0.4)',
      () async {
        // ServerAuthentication usado isoladamente: handler poderia
        // chama-lo com tipo errado. Comportamento defensivo: rejeita
        // sem consultar DAO.
        final message = Message(
          header: MessageHeader(
            type: MessageType.heartbeat,
            length: 0,
          ),
          payload: const <String, dynamic>{},
          checksum: 0,
        );
        final result = await authentication.validateAuthRequest(message);
        expect(result.isValid, isFalse);
        expect(result.errorCode, ErrorCode.invalidRequest);
        verifyNever(() => mockDao.getByServerId(any()));
      },
    );

    test(
      'should accept serverId with control characters (defesa F0.4)',
      () async {
        // serverId com chars de controle nao deve quebrar o fluxo —
        // Drift parametriza queries (SQLi safe). O teste garante que
        // o codigo nao explode e segue o fluxo normal de comparacao.
        const weirdServerId = 'srv\x00\n\r\t<script>';
        final credential = ServerCredentialsTableData(
          id: '1',
          serverId: weirdServerId,
          passwordHash: passwordHash,
          name: 'Weird',
          isActive: true,
          createdAt: DateTime.now(),
        );
        when(
          () => mockDao.getByServerId(weirdServerId),
        ).thenAnswer((_) async => credential);

        final message = createAuthRequestMessage(
          serverId: weirdServerId,
          passwordHash: passwordHash,
        );
        final result = await authentication.validateAuthRequest(message);

        expect(result.isValid, isTrue);
      },
    );

    test(
      'should reject when DAO returns credential with mismatched hash length',
      () async {
        // Defesa contra credencial corrompida no DB (hash truncado).
        // constantTimeEquals retorna false imediatamente quando lengths
        // diferem (early-return aceitavel: lengths sao publicos).
        final credential = ServerCredentialsTableData(
          id: '1',
          serverId: serverId,
          passwordHash: 'short',
          name: 'Test',
          isActive: true,
          createdAt: DateTime.now(),
        );
        when(
          () => mockDao.getByServerId(serverId),
        ).thenAnswer((_) async => credential);

        final message = createAuthRequestMessage(
          serverId: serverId,
          passwordHash: passwordHash,
        );
        final result = await authentication.validateAuthRequest(message);

        expect(result.isValid, isFalse);
        expect(result.errorCode, ErrorCode.authenticationFailed);
      },
    );
  });
}
