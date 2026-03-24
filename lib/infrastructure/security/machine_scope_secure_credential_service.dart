import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/security/credential_machine_blob_codec.dart';
import 'package:backup_database/infrastructure/security/windows_dpapi_local_machine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class MachineScopeSecureCredentialService implements ISecureCredentialService {
  MachineScopeSecureCredentialService({
    FlutterSecureStorage? legacyStorage,
  }) : _legacy = legacyStorage ?? const FlutterSecureStorage();

  static const String _blobFileSuffix = '.bdsecret';

  final FlutterSecureStorage _legacy;

  bool get _useMachineFiles => Platform.isWindows;

  Future<File> _blobFileForKey(String key) async {
    final dir = await resolveMachineSecretsDirectory();
    final name = '${sha256.convert(utf8.encode(key))}$_blobFileSuffix';
    return File(p.join(dir.path, name));
  }

  Future<void> _ensureSecretsDir() async {
    final dir = await resolveMachineSecretsDirectory();
    await dir.create(recursive: true);
  }

  Future<String?> _readMachineValue(String key) async {
    final file = await _blobFileForKey(key);
    if (!await file.exists()) {
      return null;
    }
    try {
      final cipher = await file.readAsBytes();
      final plain = unprotectWithDpapiLocalMachine(cipher);
      final decoded = decodeCredentialMachineBlob(plain);
      if (decoded.key != key) {
        LoggerService.warning(
          'Machine credential file key mismatch; ignoring corrupt entry',
        );
        return null;
      }
      return decoded.value;
    } on Object catch (e, s) {
      LoggerService.error('Failed to read machine-scope credential blob', e, s);
      return null;
    }
  }

  Future<void> _writeMachineEntry({
    required String key,
    required String value,
  }) async {
    await _ensureSecretsDir();
    final plain = encodeCredentialMachineBlob(
      logicalKey: key,
      valueUtf8: value,
    );
    final cipher = protectWithDpapiLocalMachine(plain);
    final file = await _blobFileForKey(key);
    await file.writeAsBytes(cipher, flush: true);
  }

  Future<void> _deleteMachineFile(String key) async {
    final file = await _blobFileForKey(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _migrateLegacyStringToMachine({
    required String key,
    required String value,
  }) async {
    try {
      await _writeMachineEntry(key: key, value: value);
      await _legacy.delete(key: key);
      LoggerService.info(
        'Secure credential migrated to machine-scope storage (DPAPI)',
      );
    } on Object catch (e, s) {
      LoggerService.error(
        'Failed to migrate credential to machine-scope',
        e,
        s,
      );
    }
  }

  @override
  Future<rd.Result<Unit>> storePassword({
    required String key,
    required String password,
  }) async {
    try {
      if (_useMachineFiles) {
        await _writeMachineEntry(key: key, value: password);
        await _legacy.delete(key: key);
        return const rd.Success(unit);
      }
      await _legacy.write(key: key, value: password);
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to store password for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao armazenar credencial: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<String>> getPassword({
    required String key,
  }) async {
    try {
      if (_useMachineFiles) {
        final machine = await _readMachineValue(key);
        if (machine != null) {
          return rd.Success(machine);
        }
        final legacy = await _legacy.read(key: key);
        if (legacy != null) {
          await _migrateLegacyStringToMachine(key: key, value: legacy);
          return rd.Success(legacy);
        }
        return rd.Failure(
          StorageFailure(message: 'Credencial não encontrada: $key'),
        );
      }

      final password = await _legacy.read(key: key);
      if (password == null) {
        return rd.Failure(
          StorageFailure(message: 'Credencial não encontrada: $key'),
        );
      }
      return rd.Success(password);
    } on Object catch (e, s) {
      LoggerService.error('Failed to read password for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao ler credencial: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Unit>> deletePassword({
    required String key,
  }) async {
    try {
      if (_useMachineFiles) {
        await _deleteMachineFile(key);
      }
      await _legacy.delete(key: key);
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to delete password for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao deletar credencial: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Unit>> storeToken({
    required String key,
    required Map<String, dynamic> tokenData,
  }) async {
    try {
      final jsonToken = jsonEncode(tokenData);
      if (_useMachineFiles) {
        await _writeMachineEntry(key: key, value: jsonToken);
        await _legacy.delete(key: key);
        return const rd.Success(unit);
      }
      await _legacy.write(key: key, value: jsonToken);
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to store token for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao armazenar token: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Map<String, dynamic>>> getToken({
    required String key,
  }) async {
    try {
      String? jsonToken;
      if (_useMachineFiles) {
        jsonToken = await _readMachineValue(key);
        if (jsonToken == null) {
          final legacy = await _legacy.read(key: key);
          if (legacy != null) {
            await _migrateLegacyStringToMachine(key: key, value: legacy);
            jsonToken = legacy;
          }
        }
      } else {
        jsonToken = await _legacy.read(key: key);
      }

      if (jsonToken == null) {
        return rd.Failure(
          StorageFailure(message: 'Token não encontrado: $key'),
        );
      }

      final tokenData = jsonDecode(jsonToken) as Map<String, dynamic>;
      return rd.Success(tokenData);
    } on Object catch (e, s) {
      LoggerService.error('Failed to read token for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao ler token: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Unit>> deleteToken({
    required String key,
  }) async {
    try {
      if (_useMachineFiles) {
        await _deleteMachineFile(key);
      }
      await _legacy.delete(key: key);
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to delete token for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao deletar token: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<bool>> containsKey({
    required String key,
  }) async {
    try {
      if (_useMachineFiles) {
        final file = await _blobFileForKey(key);
        if (await file.exists()) {
          return const rd.Success(true);
        }
      }
      final contains = await _legacy.containsKey(key: key);
      return rd.Success(contains);
    } on Object catch (e, s) {
      LoggerService.error('Failed to check key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao verificar chave: $key',
          originalError: e,
        ),
      );
    }
  }

  Future<Map<String, String>> _readAllMachineEntries() async {
    if (!_useMachineFiles) {
      return {};
    }
    final dir = await resolveMachineSecretsDirectory();
    if (!await dir.exists()) {
      return {};
    }
    final out = <String, String>{};
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!entity.path.toLowerCase().endsWith(_blobFileSuffix)) {
        continue;
      }
      try {
        final cipher = await entity.readAsBytes();
        final plain = unprotectWithDpapiLocalMachine(cipher);
        final decoded = decodeCredentialMachineBlob(plain);
        out[decoded.key] = decoded.value;
      } on Object catch (e, s) {
        LoggerService.debug(
          'Skip unreadable machine credential file ${entity.path}: $e',
          e,
          s,
        );
      }
    }
    return out;
  }

  @override
  Future<rd.Result<Unit>> deleteAll() async {
    try {
      if (_useMachineFiles) {
        final dir = await resolveMachineSecretsDirectory();
        if (await dir.exists()) {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is File &&
                entity.path.toLowerCase().endsWith(_blobFileSuffix)) {
              await entity.delete();
            }
          }
        }
      }
      await _legacy.deleteAll();
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to delete all credentials', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao deletar todas as credenciais',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Map<String, String>>> readAll() async {
    try {
      final legacy = await _legacy.readAll();
      final machine = await _readAllMachineEntries();
      return rd.Success({...legacy, ...machine});
    } on Object catch (e, s) {
      LoggerService.error('Failed to read all credentials', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao ler todas as credenciais',
          originalError: e,
        ),
      );
    }
  }
}
