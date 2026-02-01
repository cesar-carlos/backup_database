import 'package:backup_database/core/security/password_hasher.dart';
import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/domain/repositories/i_server_credential_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class ServerCredentialProvider extends ChangeNotifier {
  ServerCredentialProvider(this._repository) {
    loadCredentials();
  }
  final IServerCredentialRepository _repository;

  List<ServerCredential> _credentials = [];
  bool _isLoading = false;
  String? _error;

  List<ServerCredential> get credentials => _credentials;
  bool get isLoading => _isLoading;
  String? get error => _error;

  static const int _minPasswordLength = 8;

  Future<void> loadCredentials() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.getAll();

    result.fold(
      (list) {
        _credentials = list;
        _isLoading = false;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<bool> createCredential({
    required String serverId,
    required String name,
    required String plainPassword,
    required bool isActive,
    String? description,
  }) async {
    if (plainPassword.length < _minPasswordLength) {
      _error = 'A senha deve ter pelo menos $_minPasswordLength caracteres.';
      notifyListeners();
      return false;
    }

    final existingResult = await _repository.getByServerId(serverId);
    if (existingResult.isSuccess()) {
      _error = 'Já existe uma credencial com este Server ID.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

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

    return result.fold(
      (saved) {
        _credentials.add(saved);
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> updateCredential(
    ServerCredential credential, {
    String? plainPassword,
    String? name,
    bool? isActive,
    String? description,
  }) async {
    if (plainPassword != null && plainPassword.isNotEmpty) {
      if (plainPassword.length < _minPasswordLength) {
        _error = 'A senha deve ter pelo menos $_minPasswordLength caracteres.';
        notifyListeners();
        return false;
      }
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

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

    return result.fold(
      (saved) {
        final index = _credentials.indexWhere((c) => c.id == saved.id);
        if (index != -1) {
          _credentials[index] = saved;
        }
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> deleteCredential(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.delete(id);

    return result.fold(
      (_) {
        _credentials.removeWhere((c) => c.id == id);
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }
}
