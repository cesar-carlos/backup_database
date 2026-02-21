import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_credential_dao.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

class AuthValidationResult {
  const AuthValidationResult({
    required this.isValid,
    this.errorMessage,
    this.errorCode,
  });

  final bool isValid;
  final String? errorMessage;
  final ErrorCode? errorCode;
}

class ServerAuthentication {
  ServerAuthentication(
    this._dao, {
    ILicenseValidationService? licenseValidationService,
  }) : _licenseValidationService = licenseValidationService;

  final ServerCredentialDao _dao;
  final ILicenseValidationService? _licenseValidationService;

  Future<AuthValidationResult> validateAuthRequest(Message message) async {
    if (message.header.type != MessageType.authRequest) {
      return const AuthValidationResult(
        isValid: false,
        errorMessage: 'Tipo de autenticacao invalido',
        errorCode: ErrorCode.invalidRequest,
      );
    }

    final serverId = message.payload['serverId'] as String?;
    final passwordHash = message.payload['passwordHash'] as String?;
    if (serverId == null ||
        serverId.isEmpty ||
        passwordHash == null ||
        passwordHash.isEmpty) {
      LoggerService.warning(
        'ServerAuthentication: missing serverId or passwordHash',
      );
      return const AuthValidationResult(
        isValid: false,
        errorMessage: 'Credenciais incompletas',
        errorCode: ErrorCode.invalidRequest,
      );
    }

    final licenseValidationService = _licenseValidationService;
    if (licenseValidationService != null) {
      try {
        final licenseResult = await licenseValidationService.isFeatureAllowed(
          LicenseFeatures.remoteControl,
        );
        if (licenseResult.isError()) {
          final failure = licenseResult.exceptionOrNull();
          LoggerService.warning(
            'ServerAuthentication: failed to validate license feature: $failure',
          );
          return const AuthValidationResult(
            isValid: false,
            errorMessage:
                'Conexao remota bloqueada: falha ao validar licenca do servidor',
            errorCode: ErrorCode.licenseDenied,
          );
        }

        final isRemoteControlAllowed = licenseResult.getOrElse((_) => false);
        if (!isRemoteControlAllowed) {
          LoggerService.warning(
            'ServerAuthentication: remote control denied by license',
          );
          return const AuthValidationResult(
            isValid: false,
            errorMessage:
                'Conexao remota bloqueada: licenca nao permite controle remoto',
            errorCode: ErrorCode.licenseDenied,
          );
        }
      } on Object catch (e, st) {
        LoggerService.warning(
          'ServerAuthentication: exception while validating license',
          e,
          st,
        );
        return const AuthValidationResult(
          isValid: false,
          errorMessage:
              'Conexao remota bloqueada: erro ao validar licenca do servidor',
          errorCode: ErrorCode.licenseDenied,
        );
      }
    }

    final credential = await _dao.getByServerId(serverId);
    if (credential == null || !credential.isActive) {
      LoggerService.warning(
        'ServerAuthentication: no active credential for serverId',
      );
      return const AuthValidationResult(
        isValid: false,
        errorMessage: 'Credencial invalida ou inativa',
        errorCode: ErrorCode.authenticationFailed,
      );
    }

    final valid = PasswordHasher.constantTimeEquals(
      credential.passwordHash,
      passwordHash,
    );
    if (valid) {
      LoggerService.info('ServerAuthentication: success for serverId');
    } else {
      LoggerService.warning(
        'ServerAuthentication: invalid password for serverId',
      );
      return const AuthValidationResult(
        isValid: false,
        errorMessage: 'Senha ou Server ID invalidos',
        errorCode: ErrorCode.authenticationFailed,
      );
    }
    return const AuthValidationResult(isValid: true);
  }
}
