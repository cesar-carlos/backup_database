import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/domain/repositories/i_server_credential_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

const String _plainPasswordKeyPrefix = 'server_credential_plain_';

class ServerCredentialProvider extends ChangeNotifier with AsyncStateMixin {
  ServerCredentialProvider(
    this._repository,
    this._secureCredentialService,
  ) {
    loadCredentials();
  }
  final IServerCredentialRepository _repository;
  final ISecureCredentialService _secureCredentialService;

  List<ServerCredential> _credentials = [];

  List<ServerCredential> get credentials => _credentials;

  static const int _minPasswordLength = 8;

  Future<void> loadCredentials() async {
    await runAsync<void>(
      action: () async {
        final result = await _repository.getAll();
        result.fold(
          (list) => _credentials = list,
          (failure) => throw failure,
        );
      },
    );
  }

  Future<bool> createCredential({
    required String serverId,
    required String name,
    required String plainPassword,
    required bool isActive,
    String? description,
  }) async {
    if (plainPassword.length < _minPasswordLength) {
      setErrorManual(
        'A senha deve ter pelo menos $_minPasswordLength caracteres.',
      );
      return false;
    }

    final existingResult = await _repository.getByServerId(serverId);
    if (existingResult.isSuccess()) {
      setErrorManual('Já existe uma credencial com este Server ID.');
      return false;
    }

    final ok = await runAsync<bool>(
      action: () async {
        final passwordHash = PasswordHasher.hash(plainPassword, serverId);
        final credential = ServerCredential(
          id: const Uuid().v4(),
          serverId: serverId,
          passwordHash: passwordHash,
          name: name,
          isActive: isActive,
          createdAt: DateTime.now(),
          description: description,
        );

        final result = await _repository.save(credential);
        final saved = result.fold(
          (s) => s,
          (failure) => throw failure,
        );

        try {
          await _secureCredentialService.storePassword(
            key: '$_plainPasswordKeyPrefix${saved.id}',
            password: plainPassword,
          );
        } on Object catch (e, s) {
          // Rollback: a credencial está no DB mas a senha clara não foi
          // armazenada no cofre seguro. Sem rollback, o backup não conseguirá
          // autenticar contra o servidor remoto.
          LoggerService.error(
            'Falha ao armazenar senha no cofre seguro — fazendo rollback do save',
            e,
            s,
          );
          final rollback = await _repository.delete(saved.id);
          rollback.fold(
            (_) {},
            (rollbackFailure) => LoggerService.error(
              'Rollback do save da credencial falhou (registro órfão no DB)',
              rollbackFailure,
            ),
          );
          throw Exception('Falha ao armazenar senha de forma segura: $e');
        }

        _credentials = [..._credentials, saved];
        return true;
      },
    );
    return ok ?? false;
  }

  Future<bool> updateCredential(
    ServerCredential credential, {
    String? plainPassword,
    String? name,
    bool? isActive,
    String? description,
  }) async {
    if (plainPassword != null &&
        plainPassword.isNotEmpty &&
        plainPassword.length < _minPasswordLength) {
      setErrorManual(
        'A senha deve ter pelo menos $_minPasswordLength caracteres.',
      );
      return false;
    }

    final ok = await runAsync<bool>(
      action: () async {
        final passwordHash = plainPassword != null && plainPassword.isNotEmpty
            ? PasswordHasher.hash(plainPassword, credential.serverId)
            : credential.passwordHash;

        final updated = credential.copyWith(
          passwordHash: passwordHash,
          name: name ?? credential.name,
          isActive: isActive ?? credential.isActive,
          description: description ?? credential.description,
        );

        final result = await _repository.update(updated);
        final saved = result.fold(
          (s) => s,
          (failure) => throw failure,
        );

        if (plainPassword != null && plainPassword.isNotEmpty) {
          await _secureCredentialService.storePassword(
            key: '$_plainPasswordKeyPrefix${saved.id}',
            password: plainPassword,
          );
        }
        _credentials = [
          for (final c in _credentials)
            if (c.id == saved.id) saved else c,
        ];
        return true;
      },
    );
    return ok ?? false;
  }

  Future<String?> getPlainPassword(String credentialId) async {
    final result = await _secureCredentialService.getPassword(
      key: '$_plainPasswordKeyPrefix$credentialId',
    );
    return result.fold((pwd) => pwd, (_) => null);
  }

  Future<bool> deleteCredential(String id) async {
    final ok = await runAsync<bool>(
      action: () async {
        final result = await _repository.delete(id);
        result.fold(
          (_) {},
          (failure) => throw failure,
        );

        await _secureCredentialService.deletePassword(
          key: '$_plainPasswordKeyPrefix$id',
        );
        _credentials = _credentials.where((c) => c.id != id).toList();
        return true;
      },
    );
    return ok ?? false;
  }
}
