import 'dart:math';

import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/domain/repositories/i_server_credential_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:uuid/uuid.dart';

const int _defaultPasswordLength = 12;
const String _defaultCredentialName = 'Credencial padrão';
const String _plainPasswordKeyPrefix = 'server_credential_plain_';

class InitialSetupService {
  InitialSetupService(
    this._credentialRepository,
    this._secureCredentialService,
  );

  final IServerCredentialRepository _credentialRepository;
  final ISecureCredentialService _secureCredentialService;

  Future<DefaultCredentialResult?> createDefaultCredentialIfNotExists() async {
    final result = await _credentialRepository.getAll();
    if (result.isError()) {
      LoggerService.warning(
        'InitialSetupService: failed to list credentials',
        result.exceptionOrNull(),
      );
      return null;
    }
    final list = result.getOrNull()!;
    if (list.isNotEmpty) {
      return null;
    }

    final serverId = _randomAlphanumeric(8);
    final plainPassword = _randomPassword();
    final passwordHash = PasswordHasher.hash(plainPassword, serverId);
    final credential = ServerCredential(
      id: Uuid().v4(), // ignore: prefer_const_constructors - runtime id and timestamp
      serverId: serverId,
      passwordHash: passwordHash,
      name: _defaultCredentialName,
      isActive: true,
      createdAt: DateTime.now(),
      description: 'Criada automaticamente na primeira execução',
    );

    final saveResult = await _credentialRepository.save(credential);
    if (saveResult.isError()) {
      LoggerService.warning(
        'InitialSetupService: failed to save default credential',
        saveResult.exceptionOrNull(),
      );
      return null;
    }

    final saved = saveResult.getOrThrow();
    await _secureCredentialService.storePassword(
      key: '$_plainPasswordKeyPrefix${saved.id}',
      password: plainPassword,
    );

    LoggerService.info(
      'InitialSetupService: default credential created (serverId: $serverId)',
    );
    return DefaultCredentialResult(
      serverId: serverId,
      plainPassword: plainPassword,
    );
  }

  String _randomAlphanumeric(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _randomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%';
    final r = Random.secure();
    return List.generate(_defaultPasswordLength, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

class DefaultCredentialResult {
  const DefaultCredentialResult({
    required this.serverId,
    required this.plainPassword,
  });

  final String serverId;
  final String plainPassword;
}
