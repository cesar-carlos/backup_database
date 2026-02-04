import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/datasources/daos/server_credential_dao.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

class ServerAuthentication {
  ServerAuthentication(this._dao);

  final ServerCredentialDao _dao;

  Future<bool> validateAuthRequest(Message message) async {
    if (message.header.type != MessageType.authRequest) return false;

    final serverId = message.payload['serverId'] as String?;
    final passwordHash = message.payload['passwordHash'] as String?;
    if (serverId == null ||
        serverId.isEmpty ||
        passwordHash == null ||
        passwordHash.isEmpty) {
      LoggerService.warning('ServerAuthentication: missing serverId or passwordHash');
      return false;
    }

    final credential = await _dao.getByServerId(serverId);
    if (credential == null || !credential.isActive) {
      LoggerService.warning('ServerAuthentication: no active credential for serverId');
      return false;
    }

    final valid =
        PasswordHasher.constantTimeEquals(credential.passwordHash, passwordHash);
    if (valid) {
      LoggerService.info('ServerAuthentication: success for serverId');
    } else {
      LoggerService.warning('ServerAuthentication: invalid password for serverId');
    }
    return valid;
  }
}
